"""Cloud Functions (2nd gen, Python) for the Emergency Response System.
  on_incident_written   : an alert is created/changed  -> decide who to ask (dispatch engine)
  on_offer_written      : a responder answered         -> resolve who won, release contact, ask the next one if declined
  sweep_dispatch        : every minute                 -> expire unanswered offers, escalate, set silent responders Offline
  admin_assign_responder / admin_close_incident        -> manual actions for administrators (callable)
  save_text_feedback_fn : saves resident-CONFIRMED labels for retraining (consent only; sensitive messages never)
All decisions live in dispatch/core.py (tested). This file only connects them to Firebase."""
import hashlib
import os
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "ml", "scripts"))

from firebase_admin import auth as fb_auth, initialize_app, firestore
from firebase_functions import firestore_fn, https_fn, options, scheduler_fn

import dispatch  # noqa: F401  (path set-up)
from dispatch import admin_accounts as acct, config as C, core, notify, store

from phase3_functions import MAPS_SERVER_KEY, resident_request_unit, incident_route  # noqa: F401,E402  (Phase 3A)
from phase3c_functions import help_geocode, help_directions  # noqa: F401,E402  (Phase 3A.2)
from phase4d_functions import responder_sos, admin_resolve_sos, reveal_contact, send_checkin, request_more_units  # noqa: F401,E402  (Phase 4D)
from phase4d_staff import admin_list_dispatchers, admin_review_dispatcher  # noqa: F401,E402  (Phase 4D dispatcher approvals)
import phase4d_core as p4
initialize_app()
OPTS = dict(region=C.REGION, memory=options.MemoryOption.MB_512, timeout_sec=60, max_instances=20, secrets=[MAPS_SERVER_KEY])
_db = None


def db():
    global _db
    if _db is None:
        _db = firestore.client()
    return _db


def _strip(d):
    return {k: v for k, v in (d or {}).items() if k not in ("dispatch", "updatedAt")}


def _quiet(fn, label):
    """An event or metric failure must never stop dispatch."""
    try:
        fn()
    except Exception as e:  # noqa: BLE001
        print(f"[events] {label}: {type(e).__name__}")


def _record_incident_events(db, iid, old, new, now):
    """Who opened the call, when it was classified, what priority was set, when it closed."""
    uid = new.get("userId") or "system"
    if old is None:
        p4.write_event(db, iid, "incident_created", "resident", uid, {"category": new.get("category")}, "incident_created")
    else:
        if old.get("triageStatus") != new.get("triageStatus") and new.get("triageStatus") in ("quick", "complete"):
            p4.write_event(db, iid, "classified", "resident", uid,
                           {"triageStatus": new.get("triageStatus"), "priority": new.get("priority")},
                           f"classified_{new.get('triageStatus')}")
        if old.get("priority") != new.get("priority"):
            p4.write_event(db, iid, "priority_set", "resident", uid,
                           {"priority": new.get("priority"), "source": new.get("prioritySource")},
                           f"priority_set_{new.get('priority')}")
        if old.get("status") != "Cancelled" and new.get("status") == "Cancelled":
            p4.write_event(db, iid, "incident_cancelled", "resident", uid, {"from": old.get("status")}, "incident_cancelled")
        if old.get("status") != "Resolved" and new.get("status") == "Resolved":
            p4.write_event(db, iid, "incident_closed", "system", "system", {}, "incident_closed")
    acc = new.get("locationAccuracyM")
    if isinstance(acc, (int, float)) and acc > p4.LOW_ACCURACY_M and (old is None or old.get("locationAccuracyM") != acc):
        p4.raise_attention(db, iid, "low_accuracy")
    if new.get("status") in ("Cancelled", "Resolved"):
        p4.close_metrics(db, iid, new, now)


def _event_for_status(status, reason):
    """(event type, who) for an offer that moved. Withdrawals caused by the server are system events."""
    if status == "accepted":
        return "offer_accepted", "responder"
    if status == "declined":
        return "offer_declined", "responder"
    if status == "expired":
        return "offer_expired", "system"
    if status == "enroute":
        return "unit_en_route", "responder"
    if status == "arrived":
        return "unit_arrived", "responder"
    if status == "withdrawn":
        server = ("incident_cancelled", "incident_resolved", "another_unit_accepted", "role_already_filled")
        return "offer_withdrawn", "system" if reason in server else "responder"
    return None, None


def _stamp_offer_times(db, offer_id, new):
    """The phone keeps only the latest response time; stamp each status once so the completion summary has real timings."""
    status = new.get("status")
    if status not in ("accepted", "enroute", "arrived", "completed"):
        return
    if status in (new.get("offerTimes") or {}):
        return
    db.collection("offers").document(offer_id).update({f"offerTimes.{status}": firestore.SERVER_TIMESTAMP})


def _record_offer_events(db, offer_id, new, old):
    iid = new.get("incidentId")
    if not iid:
        return
    if old is None:
        p4.write_event(db, iid, "offer_sent", "system", "system",
                       {"role": new.get("role"), "wave": new.get("wave")}, f"offer_sent_{offer_id}")
        return
    _stamp_offer_times(db, offer_id, new)
    rid = new.get("responderId")
    if old.get("seenAt") is None and new.get("seenAt") is not None:
        p4.write_event(db, iid, "offer_seen", "responder", rid, {}, f"offer_seen_{offer_id}")
    if old.get("moreUnits") is None and isinstance(new.get("moreUnits"), dict):
        mu = new["moreUnits"]
        p4.write_event(db, iid, "extra_resources_requested", "responder", rid,
                       {"role": mu.get("role"), "count": mu.get("count")}, f"extra_resources_requested_{offer_id}")
        p4.raise_attention(db, iid, "extra_resources")
    t_old, t_new = old.get("transport"), new.get("transport")
    if t_old is None and isinstance(t_new, dict):
        p4.write_event(db, iid, "transport_started", "responder", rid,
                       {"destinationId": t_new.get("destinationId")}, f"transport_started_{offer_id}")
    elif isinstance(t_new, dict) and (t_old or {}).get("arrivedAt") is None and t_new.get("arrivedAt") is not None:
        p4.write_event(db, iid, "transport_arrived", "responder", rid, {}, f"transport_arrived_{offer_id}")
    if old.get("status") != new.get("status"):
        etype, who = _event_for_status(new.get("status"), new.get("withdrawReason"))
        if etype:
            p4.write_event(db, iid, etype, who, rid if who == "responder" else "system",
                           {"role": new.get("role")}, f"{etype}_{offer_id}")


def _share_caller_feedback(db, iid, old, new):
    """The unit that closed the job hears 'safe / still needs help', never who said it."""
    fb = new.get("residentFeedback")
    if not isinstance(fb, dict) or not isinstance(fb.get("safe"), bool):
        return
    if old is not None and old.get("residentFeedback") == new.get("residentFeedback"):
        return
    for s in db.collection("offers").where("incidentId", "==", iid).where("status", "==", "completed").stream():
        if (s.to_dict().get("callerFeedback") or {}).get("safe") == fb["safe"]:
            continue
        s.reference.update({"callerFeedback": {"safe": fb["safe"], "at": firestore.SERVER_TIMESTAMP}})


@firestore_fn.on_document_written(document="incidents/{incidentId}", **OPTS)
def on_incident_written(event: firestore_fn.Event[firestore_fn.Change]):
    after = event.data.after
    if after is None or not after.exists:
        return
    before = event.data.before
    new = after.to_dict() or {}
    old = before.to_dict() if before is not None and before.exists else None
    if old is not None and _strip(old) == _strip(new):
        return                                               # only our own dispatch write changed: stop (no loops)
    iid = event.params["incidentId"]
    _quiet(lambda: _record_incident_events(db(), iid, old, new, time.time()), f"incident {iid}")
    if old is None:
        _quiet(lambda: p4.snapshot_contact(db(), iid, new), f"contact {iid}")
    _quiet(lambda: _share_caller_feedback(db(), iid, old, new), f"feedback {iid}")
    store.reconcile_incident(db(), iid, time.time(), notify.send_offer_push)


@firestore_fn.on_document_written(document="offers/{offerId}", **OPTS)
def on_offer_written(event: firestore_fn.Event[firestore_fn.Change]):
    after = event.data.after
    if after is None or not after.exists:
        return
    before = event.data.before
    new = after.to_dict()
    old = before.to_dict() if before is not None and before.exists else None
    _quiet(lambda: _record_offer_events(db(), after.id, new, old), f"offer {after.id}")
    if old is None:
        return                                               # a new offer: the push was sent when it was created
    if old.get("status") == new.get("status"):
        return
    store.handle_offer_status_change(db(), after.id, new, time.time(), notify.send_offer_push)


@scheduler_fn.on_schedule(schedule="every 1 minutes", **OPTS)
def sweep_dispatch(event: scheduler_fn.ScheduledEvent) -> None:
    store.sweep(db(), time.time(), notify.send_offer_push)
    _quiet(lambda: p4.sweep_attention(db(), time.time()), "attention sweep")


@firestore_fn.on_document_created(document="incidents/{incidentId}/messages/{messageId}", **OPTS)
def on_message_created(event: firestore_fn.Event[firestore_fn.DocumentSnapshot]):
    """A message from dispatch is part of the record. Responder messages are already on the offer trail."""
    d = event.data.to_dict() or {}
    if d.get("senderRole") != "admin":
        return
    iid, mid = event.params["incidentId"], event.params["messageId"]
    _quiet(lambda: p4.write_event(db(), iid, "admin_message_sent", "admin", d.get("senderUid") or "system", {}, f"admin_message_sent_{mid}"), f"message {mid}")


@firestore_fn.on_document_written(document="incidents/{incidentId}/checkins/{checkinId}", **OPTS)
def on_checkin_written(event: firestore_fn.Event[firestore_fn.Change]):
    after = event.data.after
    if after is None or not after.exists:
        return
    new = after.to_dict() or {}
    before = event.data.before
    old = before.to_dict() if before is not None and before.exists else None
    if new.get("reply") is None or (old is not None and old.get("reply") == new.get("reply")):
        return
    iid, cid = event.params["incidentId"], event.params["checkinId"]
    snap = db().collection("incidents").document(iid).get()
    uid = (snap.to_dict() or {}).get("userId") if snap.exists else None
    _quiet(lambda: p4.write_event(db(), iid, "checkin_replied", "resident", uid or "resident", {"reply": new.get("reply")}, f"checkin_replied_{cid}"), f"checkin {cid}")


def _require_admin(req):
    if req.auth is None or (req.auth.token or {}).get("role") != "SystemAdmin":
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.PERMISSION_DENIED, "Administrators only.")


def _require_staff(req):
    """Administrator or dispatcher. Returns the event actor role ('admin' or 'dispatcher')."""
    role = (req.auth.token or {}).get("role") if req.auth is not None else None
    if role not in ("SystemAdmin", "Dispatcher"):
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.PERMISSION_DENIED, "Dispatchers and administrators only.")
    return "admin" if role == "SystemAdmin" else "dispatcher"


@https_fn.on_call(**OPTS)
def admin_assign_responder(req: https_fn.CallableRequest):
    """Manually asks one responder to attend an incident (dispatcher or administrator). A reason is required."""
    actor = _require_staff(req)
    d = req.data if isinstance(req.data, dict) else {}
    iid, rid = d.get("incidentId"), d.get("responderId")
    reason = str(d.get("reason") or "").strip()[:140]
    if len(reason) < 3:
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.INVALID_ARGUMENT, "Give a reason for the manual assignment (at least 3 characters).")
    if not isinstance(iid, str) or not isinstance(rid, str):
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.INVALID_ARGUMENT, "incidentId and responderId are required.")
    snap = db().collection("incidents").document(iid).get()
    rs = db().collection("responders").document(rid).get()
    if not snap.exists or not rs.exists:
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.NOT_FOUND, "Incident or responder not found.")
    inc = store.incident_view(iid, snap.to_dict())
    if inc["status"] not in ("Active", "SupportOnly") or inc["lat"] is None:
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.FAILED_PRECONDITION, "The incident is closed or has no location.")
    resp = store.responder_view(db(), rid, rs.to_dict())
    if not resp["verified"]:
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.FAILED_PRECONDITION, "Responder is not verified.")
    pr = core.server_priority(inc, store.table())
    required, preferred, n = core.needs(inc)
    now = time.time()
    caps = core.effective_caps(resp)
    role = d.get("role") if d.get("role") in C.ALL_CAPABILITIES else (required[0] if required else "any_responder")
    from dispatch import config
    dist = round(core.dl.haversine_km(inc["lat"], inc["lng"], resp["lat"], resp["lng"]), 2) if resp["lat"] is not None else None
    offer = {"id": f"{iid}_{rid}", "incidentId": iid, "incidentCode": inc["code"], "responderId": rid, "role": role, "wave": 0, "status": "offered",
             "createdAt": now, "expiresAt": now + config.MANUAL_OFFER_SECONDS, "distanceKm": dist if dist is not None else 0, "priority": pr["priority"],
             "category": inc["category"], "subtype": inc["subtype"], "covers": sorted(set(caps) & set(required + preferred)), "manual": True,
             "location": {"lat": inc["lat"], "lng": inc["lng"]}, **core.briefing_fields(inc, pr["priority"], required, n or {})}
    ref = db().collection("offers").document(offer["id"])
    doc = store._offer_doc(offer)
    ref.set(doc)                                              # an administrator may re-ask a responder who declined before
    store.audit(db(), "offer_created_manual", iid, responderId=rid, by=req.auth.uid)
    _quiet(lambda: p4.write_event(db(), iid, "admin_assigned", actor, req.auth.uid,
                                  {"role": role, "reason": reason}, f"admin_assigned_{offer['id']}"), f"assign {iid}")
    notify.send_offer_push(db(), offer)
    return {"ok": True, "offerId": offer["id"]}


@https_fn.on_call(**OPTS)
def admin_close_incident(req: https_fn.CallableRequest):
    """Dispatchers and administrators close an incident with a required outcome note."""
    actor = _require_staff(req)
    d = req.data if isinstance(req.data, dict) else {}
    iid, note = d.get("incidentId"), str(d.get("note") or "").strip()[:280]
    if not isinstance(iid, str):
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.INVALID_ARGUMENT, "incidentId is required.")
    if len(note) < 3:
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.INVALID_ARGUMENT, "Write the outcome (at least 3 characters).")
    ref = db().collection("incidents").document(iid)
    snap = ref.get()
    if not snap.exists:
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.NOT_FOUND, "Incident not found.")
    if snap.to_dict().get("status") not in ("Active", "SupportOnly"):
        return {"ok": True, "already": True}
    ref.update({"status": "Resolved", "resolvedAt": firestore.SERVER_TIMESTAMP, "resolution": {"by": req.auth.uid, "note": note, "byRole": actor}})
    store.audit(db(), "incident_closed_by_admin", iid, by=req.auth.uid, note=note)
    _quiet(lambda: p4.write_event(db(), iid, "incident_closed", actor, req.auth.uid, {"by": actor}, "incident_closed"), f"close {iid}")
    return {"ok": True}


# ---- administrator accounts (only an existing administrator may call these) ----
_CODES = {"invalid-argument": https_fn.FunctionsErrorCode.INVALID_ARGUMENT, "failed-precondition": https_fn.FunctionsErrorCode.FAILED_PRECONDITION,
          "not-found": https_fn.FunctionsErrorCode.NOT_FOUND}


def _admin_call(fn):
    try:
        return fn()
    except acct.AdminError as e:
        raise https_fn.HttpsError(_CODES.get(e.code, https_fn.FunctionsErrorCode.INTERNAL), e.message)


@https_fn.on_call(**OPTS)
def admin_list_admins(req: https_fn.CallableRequest):
    _require_admin(req)
    return {"admins": [{**a, "createdAt": a["createdAt"], "lastSignInAt": a["lastSignInAt"]} for a in _admin_call(lambda: acct.list_admins(fb_auth))], "me": req.auth.uid}


@https_fn.on_call(**OPTS)
def admin_grant_admin(req: https_fn.CallableRequest):
    """Adds an administrator by e-mail. New people get a one-time link to set their own password (no password is ever chosen for them)."""
    _require_admin(req)
    d = req.data if isinstance(req.data, dict) else {}
    res = _admin_call(lambda: acct.grant(fb_auth, d.get("email")))
    store.audit(db(), "admin_granted", "-", by=req.auth.uid, target=res["uid"], email=res["email"], created=res["created"])
    return res


@https_fn.on_call(**OPTS)
def admin_revoke_admin(req: https_fn.CallableRequest):
    _require_admin(req)
    d = req.data if isinstance(req.data, dict) else {}
    res = _admin_call(lambda: acct.revoke(fb_auth, req.auth.uid, d.get("uid")))
    store.audit(db(), "admin_revoked", "-", by=req.auth.uid, target=res["uid"], email=res["email"])
    return {"ok": True}


# ---- resident-confirmed text feedback (optional: needs ml/scripts/feedback_store.py) ----
try:
    import feedback_store as fb

    @https_fn.on_call(**OPTS)
    def save_text_feedback_fn(req: https_fn.CallableRequest):
        """Never blocks an emergency: the app ignores the answer."""
        try:
            uid = req.auth.uid if req.auth else None
            record, why = fb.prepare_record(req.data, uid, os.environ.get("FEEDBACK_SALT", ""))
            if record is None:
                return {"stored": False, "reason": why}
            doc_id = hashlib.sha256((record["contributor"] + record["text"].lower()).encode()).hexdigest()[:24]
            record["created"] = firestore.SERVER_TIMESTAMP
            db().collection("text_feedback").document(doc_id).set(record)
            return {"stored": True}
        except Exception as e:  # noqa: BLE001
            return {"stored": False, "reason": f"error: {type(e).__name__}"}
except ImportError:
    pass
