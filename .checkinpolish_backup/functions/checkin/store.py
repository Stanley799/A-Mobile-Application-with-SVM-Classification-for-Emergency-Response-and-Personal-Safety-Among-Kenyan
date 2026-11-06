"""Connects the check-in brain (core.py) to Firestore, SMS, voice and push. Thin on purpose: every decision is made in core.py.

Order of work for each check-in, every minute:  evaluate -> save status + esc FIRST -> then carry out the actions.
So a retried or overlapping run never texts the same contact twice. A send that fails is released for a retry (3 tries).
`db` is a Firestore client (or the in-memory fake in tests). `io` bundles the senders so tests can fake them.
"""
import datetime as dt
import hmac
import secrets
from types import SimpleNamespace

from google.api_core.exceptions import AlreadyExists
from google.cloud.firestore import GeoPoint, SERVER_TIMESTAMP

from . import core, sender

COLL = "safetyCheckins"
OUTBOX = "checkinOutbox"
OPEN = core.OPEN
MAX_TRIES = 3


def make_io(push=None, link=None, sms=None, voice=None):
    """push(uid, title, body, data) ; link(checkin_id, contact_id, token) -> str ; sms(to, text) ; voice(to, client_request_id)."""
    return SimpleNamespace(push=push or (lambda *a, **k: False), link=link or (lambda *a: None),
                           sms=sms or sender.send_sms, voice=voice or sender.send_voice)


def epoch(v):
    if v is None:
        return None
    if isinstance(v, (int, float)):
        return float(v)
    return float(v.timestamp()) if hasattr(v, "timestamp") else None


def when(ts):
    return dt.datetime.fromtimestamp(ts, tz=dt.timezone.utc)


def to_core(d):
    c = dict(d)
    c["expiryTime"] = epoch(d.get("expiryTime"))
    c["lastSeenAt"] = epoch(d.get("lastSeenAt"))
    return c


def _sms_view(c):
    """What contacts may see: location and 'last seen' only if the user chose to share them."""
    v = dict(c)
    if not (c.get("plan") or {}).get("shareLocation"):
        v["lastLocation"] = None
        v["lastSeenAt"] = None
    return v


def _contact(c, contact_id):
    return next((ct for ct in core.contacts_of(c) if ct["id"] == contact_id), None)


def new_token():
    return secrets.token_urlsafe(9)


def ensure_tokens(c, esc):
    """Every contact gets a private link token. Returns True when something was added."""
    toks = esc.setdefault("tokens", {})
    added = False
    for ct in core.contacts_of(c):
        if ct["id"] not in toks:
            toks[ct["id"]] = new_token()
            added = True
    return added


def log(db, checkin_id, kind, contact_id, to, res):
    db.collection(OUTBOX).add({"checkinId": checkin_id, "type": kind, "contactId": contact_id, "to": sender.mask(to), "ok": bool(res.get("ok")),
                               "mode": res.get("mode"), "detail": res.get("detail"), "at": SERVER_TIMESTAMP})


# ---------------- carrying out actions ----------------
def perform(db, checkin_id, c, esc, a, io, now):
    """Returns True on success. c = core view (with the new esc already merged)."""
    t = a["type"]
    uid = c.get("userId")
    if t == "remind_user":
        title, body = {
            "before": ("Check-in due soon", "Tap to confirm you are safe, or add more time."),
            "due": ("Check-in due now", "Tap to confirm you are safe. Your contacts are told in a few minutes."),
            "overdue": ("Please check in", "Your contacts will be alerted soon."),
        }.get(a.get("kind"), ("Check-in", "Please open Nusuru."))
        return bool(io.push(uid, title, body, {"type": "checkin", "checkinId": checkin_id}))
    if t in ("sms_contact", "voice_contact", "push_contact", "sms_all_clear"):
        ct = _contact(c, a["contactId"])
        if ct is None:
            return True
        token = (esc.get("tokens") or {}).get(ct["id"], "")
        view = _sms_view(c)
        if t == "sms_contact":
            res = io.sms(ct["phone"], core.sms_text(view, ct["name"], io.link(checkin_id, ct["id"], token)))
        elif t == "sms_all_clear":
            res = io.sms(ct["phone"], core.all_clear_text(c))
        elif t == "voice_contact":
            res = io.voice(ct["phone"], "%s|%s|%s" % (checkin_id, ct["id"], token))
        else:
            ok = io.push(ct.get("uid"), "Safety check-in", core.sms_text(view, ct["name"]), {"type": "checkin_contact", "checkinId": checkin_id})
            res = {"ok": bool(ok), "mode": "push", "detail": "push"}
        log(db, checkin_id, t, ct["id"], ct["phone"], res)
        return bool(res.get("ok"))
    if t == "create_incident":
        return create_incident(db, checkin_id, c, esc, a, now)
    if t == "cancel_incident":
        ref = db.collection("incidents").document(a["incidentId"])
        snap = ref.get()
        if snap.exists and (snap.to_dict() or {}).get("status") == "Active":
            ref.update({"status": "Cancelled", "updatedAt": SERVER_TIMESTAMP})
        return True
    return True


def create_incident(db, checkin_id, c, esc, a, now):
    """Level 2: an ordinary alert is created for the user, so the normal dispatch engine finds responders. Same id twice = no second alert."""
    iid = "INC-CHK-%s" % checkin_id
    loc = c.get("lastLocation") or {}
    point = GeoPoint(loc["lat"], loc["lng"]) if loc.get("lat") is not None and loc.get("lng") is not None else None
    doc = {
        "userId": c["userId"], "category": "Other / General", "status": "Active", "location": point,
        "priority": "High", "prioritySource": "safe_fallback", "needsHumanReview": True, "triageStatus": "pending",
        "createdAt": SERVER_TIMESTAMP, "updatedAt": SERVER_TIMESTAMP,
        "source": "safety_checkin", "checkinId": checkin_id, "checkinReason": a.get("reason"),
    }
    if loc.get("acc") is not None:
        doc["locationSource"] = "gps"
        doc["locationAccuracyM"] = int(round(loc["acc"]))
    try:
        db.collection("incidents").document(iid).create(doc)
    except AlreadyExists:
        pass
    esc["incidentId"] = iid
    return True


# ---------------- one check-in ----------------
def _incident_state(db, esc):
    iid = esc.get("incidentId")
    if not iid:
        return None
    snap = db.collection("incidents").document(iid).get()
    return (snap.to_dict() or {}).get("status") if snap.exists else None


def process(db, checkin_id, d, now, io):
    """Evaluate one check-in and act. Returns the list of action types done (for logs and tests)."""
    c = to_core(d)
    if c.get("status") == "Level2":
        st = _incident_state(db, c.get("esc") or {})
        if st in ("Resolved", "Cancelled"):
            c["esc"] = dict(c.get("esc") or {}, incidentResolved=True)
    before_resolved = (c.get("esc") or {}).get("incidentResolved")
    res = core.evaluate(c, now)
    esc = res["esc"]
    tok_added = ensure_tokens(c, esc) if res["status"] in OPEN else False
    if not (res["changed"] or tok_added or before_resolved != (d.get("esc") or {}).get("incidentResolved")):
        return []
    fresh = db.collection(COLL).document(checkin_id).get()
    if not fresh.exists or (fresh.to_dict() or {}).get("status") != d.get("status"):
        return []                                    # the user or another run changed it meanwhile: do nothing this minute
    db.collection(COLL).document(checkin_id).update({"status": res["status"], "esc": esc, "updatedAt": SERVER_TIMESTAMP})
    merged = dict(c, status=res["status"], esc=esc)
    done, dirty = [], False
    for a in res["actions"]:
        try:
            ok = perform(db, checkin_id, merged, esc, a, io, now)
        except Exception as e:  # noqa: BLE001
            print("[checkin] %s %s: %s: %s" % (checkin_id, a["type"], type(e).__name__, e))
            ok = False
        if ok:
            done.append(a["type"])
            continue
        key = {"sms_contact": ("smsSent", "sms"), "voice_contact": ("voiceCalled", "voice"), "push_contact": ("pushSent", "push")}.get(a["type"])
        if key and a.get("contactId"):
            tag = "%s:%s" % (key[1], a["contactId"])
            n = esc.setdefault("tries", {}).get(tag, 0) + 1
            esc["tries"][tag] = n
            if n < MAX_TRIES:
                (esc.get(key[0]) or {}).pop(a["contactId"], None)      # released: the next minute tries again
            dirty = True
    if "create_incident" in done or dirty:
        db.collection(COLL).document(checkin_id).update({"esc": esc, "updatedAt": SERVER_TIMESTAMP})
    return done


def sweep(db, now, io):
    """Every minute. Only v2 check-ins (those with a plan) are touched; older ones are left exactly as they were."""
    n = 0
    found = {}
    for status in OPEN:                                 # read everything first, so one check-in is handled once per minute
        for snap in list(db.collection(COLL).where("status", "==", status).stream()):
            found[snap.id] = snap.to_dict() or {}
    for cid, d in found.items():
        if not d.get("plan"):
            continue
        try:
            n += 1 if process(db, cid, d, now, io) else 0
        except Exception as e:  # noqa: BLE001
            print("[checkin] %s: %s: %s" % (cid, type(e).__name__, e))
    return n


# ---------------- the user closes it ----------------
def settle(db, checkin_id, now, io):
    """The check-in just became CheckedIn or Cancelled. Tell contacts it was a false alarm and withdraw any alert. Safe to repeat."""
    snap = db.collection(COLL).document(checkin_id).get()
    d = snap.to_dict() if snap.exists else None
    if not d or not d.get("plan") or d.get("status") not in ("CheckedIn", "Cancelled"):
        return []
    c = to_core(d)
    esc0 = c.get("esc") or {}
    if esc0.get("allClearSent") or int(esc0.get("level") or 0) < 1:
        return []
    c["status"] = "Active"                                  # on_user_close ignores terminal states, so ask it as if still open
    res = core.on_user_close(c, d["status"], now)
    esc = res["esc"]
    db.collection(COLL).document(checkin_id).update({"esc": esc})
    merged = dict(c, status=d["status"], esc=esc)
    for a in res["actions"]:
        try:
            perform(db, checkin_id, merged, esc, a, io, now)
        except Exception as e:  # noqa: BLE001
            print("[checkin] %s %s: %s: %s" % (checkin_id, a["type"], type(e).__name__, e))
    return [a["type"] for a in res["actions"]]


# ---------------- calls from the app ----------------
def start(db, uid, owner_first, duration_sec, plan, note, now, loc=None):
    """Creates a v2 check-in. Raises ValueError(list_of_plain_problems) when the plan is not acceptable."""
    plan = dict(plan or {})
    problems = core.validate_plan(duration_sec, plan)
    for status in OPEN:
        if any(True for _ in db.collection(COLL).where("userId", "==", uid).where("status", "==", status).stream()):
            problems.append("You already have a check-in running.")
            break
    if problems:
        raise ValueError(problems)
    contacts = []
    for i, ct in enumerate(plan.get("contacts") or []):
        contacts.append({"id": str(ct.get("id") or i + 1), "name": str(ct.get("name") or "")[:60], "phone": sender.normalize_phone(ct.get("phone")),
                         "methods": [m for m in (ct.get("methods") or ["sms"]) if m in core.METHODS] or ["sms"],
                         **({"uid": ct["uid"]} if ct.get("uid") else {})})
    clean = {k: plan[k] for k in core.DEFAULTS if k in plan and plan[k] is not None}
    clean["contacts"] = contacts
    esc = {"level": 0, "tokens": {ct["id"]: new_token() for ct in contacts}}
    doc = {
        "userId": uid, "startTime": when(now), "expiryTime": when(now + duration_sec), "status": "Active",
        "durationMinutes": int(round(duration_sec / 60.0)), "createdAt": SERVER_TIMESTAMP, "updatedAt": SERVER_TIMESTAMP,
        "plan": clean, "note": " ".join(str(note or "").split())[:200], "ownerFirstName": (owner_first or "")[:30], "esc": esc, "v": 2,
        "lastSeenAt": when(now),
    }
    if loc and loc.get("lat") is not None and loc.get("lng") is not None:
        doc["lastLocation"] = {"lat": float(loc["lat"]), "lng": float(loc["lng"]), "acc": loc.get("acc")}
    cid = "CK" + secrets.token_hex(8)
    db.collection(COLL).document(cid).create(doc)
    grace = clean.get("graceSec", core.DEFAULTS["graceSec"])
    return {"id": cid, "expiryTime": now + duration_sec, "fallbackAt": core.offline_fallback_at(now + duration_sec, grace)}


def _owned(db, uid, checkin_id):
    snap = db.collection(COLL).document(checkin_id).get()
    d = snap.to_dict() if snap.exists else None
    if not d or d.get("userId") != uid:
        raise LookupError("not found")
    return d


def heartbeat(db, uid, checkin_id, lat, lng, acc, now):
    d = _owned(db, uid, checkin_id)
    if d.get("status") not in OPEN:
        return {"open": False, "status": d.get("status")}
    upd = {"lastSeenAt": when(now), "updatedAt": SERVER_TIMESTAMP}
    if isinstance(lat, (int, float)) and isinstance(lng, (int, float)) and -90 <= lat <= 90 and -180 <= lng <= 180:
        upd["lastLocation"] = {"lat": float(lat), "lng": float(lng), "acc": acc if isinstance(acc, (int, float)) else None}
    db.collection(COLL).document(checkin_id).update(upd)
    return {"open": True, "status": d.get("status")}


def close(db, uid, checkin_id, new_status, now, io):
    if new_status not in ("CheckedIn", "Cancelled"):
        raise ValueError(["Status must be CheckedIn or Cancelled."])
    d = _owned(db, uid, checkin_id)
    if d.get("status") in core.TERMINAL:
        return {"status": d.get("status")}
    db.collection(COLL).document(checkin_id).update({"status": new_status, "updatedAt": SERVER_TIMESTAMP})
    settle(db, checkin_id, now, io)
    return {"status": new_status}


# ---------------- a contact answers (web page or keypad) ----------------
def _check_token(d, contact_id, token):
    expected = ((d.get("esc") or {}).get("tokens") or {}).get(contact_id)
    return bool(expected) and hmac.compare_digest(str(expected), str(token or ""))


def contact_ack(db, checkin_id, contact_id, token, kind, now, io):
    """-> 'ok' | 'not_found' | 'bad_token' | 'not_applicable'."""
    snap = db.collection(COLL).document(checkin_id).get()
    d = snap.to_dict() if snap.exists else None
    if not d or not d.get("plan"):
        return "not_found"
    if not _check_token(d, contact_id, token):
        return "bad_token"
    esc = core.acknowledge(to_core(d), contact_id, kind, now)
    if esc is None:
        return "not_applicable"
    db.collection(COLL).document(checkin_id).update({"esc": esc, "updatedAt": SERVER_TIMESTAMP})
    process(db, checkin_id, dict(d, esc=esc), now, io)         # "cannot reach" escalates right away
    return "ok"


def view_for_page(db, checkin_id, contact_id, token):
    """-> (core view, contact name, share_location) or None when the link is wrong."""
    snap = db.collection(COLL).document(checkin_id).get()
    d = snap.to_dict() if snap.exists else None
    if not d or not d.get("plan") or not _check_token(d, contact_id, token):
        return None
    c = to_core(d)
    ct = _contact(c, contact_id)
    if ct is None:
        return None
    return c, ct["name"], bool((d.get("plan") or {}).get("shareLocation"))
