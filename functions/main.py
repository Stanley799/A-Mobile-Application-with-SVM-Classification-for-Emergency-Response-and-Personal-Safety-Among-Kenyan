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

initialize_app()
OPTS = dict(region=C.REGION, memory=options.MemoryOption.MB_512, timeout_sec=60, max_instances=20)
_db = None


def db():
    global _db
    if _db is None:
        _db = firestore.client()
    return _db


def _strip(d):
    return {k: v for k, v in (d or {}).items() if k not in ("dispatch", "updatedAt")}


@firestore_fn.on_document_written(document="incidents/{incidentId}", **OPTS)
def on_incident_written(event: firestore_fn.Event[firestore_fn.Change]):
    after = event.data.after
    if after is None or not after.exists:
        return
    before = event.data.before
    if before is not None and before.exists and _strip(before.to_dict()) == _strip(after.to_dict()):
        return                                               # only our own dispatch write changed: stop (no loops)
    store.reconcile_incident(db(), event.params["incidentId"], time.time(), notify.send_offer_push)


@firestore_fn.on_document_written(document="offers/{offerId}", **OPTS)
def on_offer_written(event: firestore_fn.Event[firestore_fn.Change]):
    after = event.data.after
    if after is None or not after.exists:
        return
    before = event.data.before
    new = after.to_dict()
    old = before.to_dict() if before is not None and before.exists else None
    if old is not None and old.get("status") == new.get("status"):
        return
    if old is None:
        return                                               # a new offer: the push was sent when it was created
    store.handle_offer_status_change(db(), after.id, new, time.time(), notify.send_offer_push)


@scheduler_fn.on_schedule(schedule="every 1 minutes", **OPTS)
def sweep_dispatch(event: scheduler_fn.ScheduledEvent) -> None:
    store.sweep(db(), time.time(), notify.send_offer_push)


def _require_admin(req):
    if req.auth is None or (req.auth.token or {}).get("role") != "SystemAdmin":
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.PERMISSION_DENIED, "Administrators only.")


@https_fn.on_call(**OPTS)
def admin_assign_responder(req: https_fn.CallableRequest):
    """Manually asks one responder to attend an incident (used when automatic dispatch found nobody)."""
    _require_admin(req)
    d = req.data if isinstance(req.data, dict) else {}
    iid, rid = d.get("incidentId"), d.get("responderId")
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
    notify.send_offer_push(db(), offer)
    return {"ok": True, "offerId": offer["id"]}


@https_fn.on_call(**OPTS)
def admin_close_incident(req: https_fn.CallableRequest):
    _require_admin(req)
    d = req.data if isinstance(req.data, dict) else {}
    iid, note = d.get("incidentId"), str(d.get("note", ""))[:280]
    if not isinstance(iid, str):
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.INVALID_ARGUMENT, "incidentId is required.")
    ref = db().collection("incidents").document(iid)
    snap = ref.get()
    if not snap.exists:
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.NOT_FOUND, "Incident not found.")
    if snap.to_dict().get("status") not in ("Active", "SupportOnly"):
        return {"ok": True, "already": True}
    ref.update({"status": "Resolved", "resolvedAt": firestore.SERVER_TIMESTAMP, "resolution": {"by": req.auth.uid, "note": note}})
    store.audit(db(), "incident_closed_by_admin", iid, by=req.auth.uid, note=note)
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
