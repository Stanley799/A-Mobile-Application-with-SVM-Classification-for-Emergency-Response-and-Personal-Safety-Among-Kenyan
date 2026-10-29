"""Reads and writes Firestore for the dispatch engine. Thin on purpose: all decisions are made in core.py.
`db` is a firestore client (or the in-memory fake used by tests)."""
import datetime as dt
import json
import os

from google.api_core.exceptions import AlreadyExists
from google.cloud.firestore import GeoPoint, SERVER_TIMESTAMP

from . import config as C
from . import core

_TABLE = None


def table():
    global _TABLE
    if _TABLE is None:
        with open(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "ml", "models", "decision_table.json"), encoding="utf-8") as f:
            _TABLE = json.load(f)
    return _TABLE


def epoch(v):
    if v is None:
        return None
    if isinstance(v, (int, float)):
        return float(v)
    if isinstance(v, dt.datetime):
        return (v if v.tzinfo else v.replace(tzinfo=dt.timezone.utc)).timestamp()
    return None


def when(e):
    return dt.datetime.fromtimestamp(e, tz=dt.timezone.utc) if e is not None else None


def incident_view(doc_id, d):
    loc = d.get("location")
    triage = d.get("triage") if isinstance(d.get("triage"), dict) else {}
    return {"id": doc_id, "code": d.get("incidentCode") or doc_id, "userId": d.get("userId"), "status": d.get("status"),
            "category": d.get("category"), "subtype": d.get("subtype"), "triageStatus": d.get("triageStatus", "pending"),
            "answers": triage.get("answers") if isinstance(triage.get("answers"), dict) else {},
            "lat": getattr(loc, "latitude", None), "lng": getattr(loc, "longitude", None),
            "createdAt": epoch(d.get("createdAt")), "freeText": d.get("description") or "", "dispatch": d.get("dispatch")}


def _user(db, uid):
    s = db.collection("users").document(uid).get()
    return s.to_dict() if s.exists else {}


def responder_view(db, rid, r, users=None):
    u = users if users is not None else _user(db, rid)
    return {"id": rid, "name": r.get("organizationName") or rid, "type": r.get("organizationType"), "phone": u.get("phoneNumber", ""),
            "lat": r.get("currentLatitude"), "lng": r.get("currentLongitude"), "status": str(r.get("availabilityStatus", "Offline")).lower(),
            "capabilities": r.get("capabilities"), "last_seen": epoch(r.get("lastSeenAt")), "verified": r.get("verificationStatus") == "Verified"}


def available_responders(db):
    out = []
    q = db.collection("responders").where("verificationStatus", "==", "Verified").where("availabilityStatus", "==", "Available")
    for s in q.stream():
        out.append(responder_view(db, s.id, s.to_dict()))
    return out


def offers_for(db, incident_id):
    out = []
    for s in db.collection("offers").where("incidentId", "==", incident_id).stream():
        d = s.to_dict()
        out.append({**d, "id": s.id, "createdAt": epoch(d.get("createdAt")), "expiresAt": epoch(d.get("expiresAt")), "respondedAt": epoch(d.get("respondedAt"))})
    return out


def _offer_doc(o):
    d = {k: v for k, v in o.items() if k not in ("id", "location", "createdAt", "expiresAt")}
    d["location"] = GeoPoint(o["location"]["lat"], o["location"]["lng"])
    d["createdAt"] = when(o["createdAt"])
    d["expiresAt"] = when(o["expiresAt"])
    d.update({"respondedAt": None, "resident": None, "updatedAt": SERVER_TIMESTAMP})
    return d


def audit(db, action, incident_id, **detail):
    try:
        db.collection("auditLogs").add({"action": action, "incidentId": incident_id, "at": SERVER_TIMESTAMP, **detail})
    except Exception:  # noqa: BLE001 - an audit failure must never stop a dispatch
        pass


def apply_actions(db, actions, notify=None):
    created = []
    for a in actions:
        ref = None
        try:
            if a["type"] == "create_offer":
                ref = db.collection("offers").document(a["offer"]["id"])
                try:
                    ref.create(_offer_doc(a["offer"]))
                    created.append(a["offer"])
                    audit(db, "offer_created", a["offer"]["incidentId"], responderId=a["offer"]["responderId"], role=a["offer"]["role"], wave=a["offer"]["wave"])
                except AlreadyExists:
                    pass
                continue
            ref = db.collection("offers").document(a["id"])
            snap = ref.get()
            if not snap.exists:
                continue
            cur = snap.to_dict().get("status")
            if a["type"] == "expire_offer" and cur == "offered":
                ref.update({"status": "expired", "updatedAt": SERVER_TIMESTAMP}); audit(db, "offer_expired", snap.to_dict().get("incidentId"), responderId=snap.to_dict().get("responderId"))
            elif a["type"] == "withdraw_offer" and cur in C.ACTIVE_OFFER:
                if cur in ("accepted", "enroute", "arrived"):
                    set_responder_status(db, snap.to_dict().get("responderId"), "Available")
                ref.update({"status": "withdrawn", "withdrawReason": a["reason"], "updatedAt": SERVER_TIMESTAMP}); audit(db, "offer_withdrawn", snap.to_dict().get("incidentId"), responderId=snap.to_dict().get("responderId"), reason=a["reason"])
            elif a["type"] == "update_offer" and cur in C.ACTIVE_OFFER:
                f = dict(a["fields"])
                if "location" in f:
                    f["location"] = GeoPoint(f["location"]["lat"], f["location"]["lng"])
                f["updatedAt"] = SERVER_TIMESTAMP
                ref.update(f)
        except Exception as e:  # noqa: BLE001 - one bad action must not block the others
            print(f"[dispatch] action {a.get('type')} failed: {type(e).__name__}: {e}")
    if notify:
        for o in created:
            try:
                notify(db, o)
            except Exception as e:  # noqa: BLE001
                print(f"[dispatch] push failed: {type(e).__name__}: {e}")
    return created


def enrich_units(db, units):
    out = []
    for u in units:
        s = db.collection("responders").document(u["responderId"]).get()
        r = s.to_dict() if s.exists else {}
        v = responder_view(db, u["responderId"], r)
        out.append({"role": u["role"], "name": v["name"], "orgType": v["type"], "phone": v["phone"], "status": u["status"], "distanceKm": u.get("distanceKm")})
    return out


def write_dispatch(db, incident_id, current, summary):
    """Writes incident.dispatch only when it changed (otherwise the trigger would loop)."""
    new = {k: v for k, v in summary.items()}
    new["units"] = enrich_units(db, summary.get("units", []))
    old = {k: v for k, v in (current or {}).items() if k != "updatedAt"}
    if old == new:
        return False
    ref = db.collection("incidents").document(incident_id)
    upd = {"dispatch": {**new, "updatedAt": SERVER_TIMESTAMP}}
    if new["state"] == "completed":
        snap = ref.get().to_dict() or {}
        if snap.get("status") == "Active":
            upd.update({"status": "Resolved", "resolvedAt": SERVER_TIMESTAMP})
    ref.update(upd)
    return True


def set_responder_status(db, rid, status):
    """The server marks a responder Busy while they hold a job and Available again when it ends (unless they went Offline themselves)."""
    try:
        ref = db.collection("responders").document(rid)
        cur = (ref.get().to_dict() or {}).get("availabilityStatus")
        if status == "Busy" and cur == "Available" or status == "Available" and cur == "Busy":
            ref.update({"availabilityStatus": status})
    except Exception as e:  # noqa: BLE001
        print(f"[dispatch] could not set responder {rid} {status}: {type(e).__name__}")


def release_resident(db, offer, incident):
    """After a responder accepts they receive the resident's first name and phone, nothing else."""
    if offer.get("resident"):
        return
    u = _user(db, incident["userId"])
    db.collection("offers").document(offer["id"]).update({"resident": {"firstName": u.get("firstName", ""), "phone": u.get("phoneNumber", "")}})
    audit(db, "contact_released", incident["id"], responderId=offer["responderId"])


def _incident_context(raw):
    """The caller's landmark and how precise the fix was. Extras: missing values simply do not travel."""
    out = {}
    lm = raw.get("landmark")
    if isinstance(lm, str) and lm.strip():
        out["landmark"] = lm.strip()[:120]
    acc = raw.get("locationAccuracyM")
    if isinstance(acc, (int, float)) and not isinstance(acc, bool):
        out["locationAccuracyM"] = int(round(acc))
    return out


def _sync_offer_context(db, incident_id, raw):
    """Puts the landmark and accuracy on new and still-open offers. Never touches status or planning fields."""
    ctx = _incident_context(raw)
    if not ctx:
        return
    try:
        for s in db.collection("offers").where("incidentId", "==", incident_id).stream():
            d = s.to_dict()
            if d.get("status") not in C.ACTIVE_OFFER:
                continue
            patch = {k: v for k, v in ctx.items() if d.get(k) != v}
            if patch:
                s.reference.update(patch)
    except Exception as e:  # noqa: BLE001 - the offer is already usable without it
        print(f"[dispatch] offer context {incident_id}: {type(e).__name__}: {e}")


def reconcile_incident(db, incident_id, now, notify=None):
    snap = db.collection("incidents").document(incident_id).get()
    if not snap.exists:
        return None
    raw = snap.to_dict() or {}
    inc = incident_view(incident_id, raw)
    if not inc["category"]:
        return None
    offers = offers_for(db, incident_id)
    res = core.reconcile(inc, available_responders(db), offers, now, table())
    apply_actions(db, res["actions"], notify)
    _sync_offer_context(db, incident_id, raw)
    write_dispatch(db, incident_id, inc.get("dispatch"), res["dispatch"])
    try:                                    # help options for the resident map; must never stop dispatch
        from . import options_store
        options_store.refresh(db, incident_id, inc, res["dispatch"], now)
    except Exception as e:  # noqa: BLE001
        print(f"[options] {incident_id}: {type(e).__name__}: {e}")
    return res


def handle_offer_status_change(db, offer_id, new, now, notify=None):
    """A responder moved an offer forward (or declined). Decide the winner, release contact, then re-plan."""
    incident_id, status = new["incidentId"], new.get("status")
    if status in C.ACCEPTED_OFFER:
        snap = db.collection("incidents").document(incident_id).get()
        if snap.exists:
            inc = incident_view(incident_id, snap.to_dict())
            required, _p, _n = core.needs(inc)
            apply_actions(db, core.resolve_acceptance(required, offers_for(db, incident_id)))
            mine = next((o for o in offers_for(db, incident_id) if o["id"] == offer_id), None)
            if mine and mine["status"] in C.ACCEPTED_OFFER:
                release_resident(db, mine, inc)
                set_responder_status(db, mine["responderId"], "Available" if mine["status"] == "completed" else "Busy")
                audit(db, "offer_" + status, incident_id, responderId=new.get("responderId"))
    elif status == "declined":
        audit(db, "offer_declined", incident_id, responderId=new.get("responderId"))
    return reconcile_incident(db, incident_id, now, notify)


def sweep(db, now, notify=None):
    """Runs every minute: expire unanswered offers, re-plan unfinished incidents, set silent responders Offline."""
    seen = set()
    for s in db.collection("offers").where("status", "==", "offered").stream():
        d = s.to_dict()
        e = epoch(d.get("expiresAt"))
        if e is not None and e <= now:
            seen.add(d["incidentId"])
    for s in db.collection("incidents").where("status", "==", "Active").stream():
        d = s.to_dict()
        state = (d.get("dispatch") or {}).get("state")
        age = now - (epoch(d.get("createdAt")) or now)
        if age <= C.ACTIVE_WINDOW_SECONDS and state in (None, "awaiting_details", "waiting_location", "dispatching", "partially_assigned", "unfilled"):
            seen.add(s.id)
    for iid in sorted(seen):
        try:
            reconcile_incident(db, iid, now, notify)
        except Exception as e:  # noqa: BLE001
            print(f"[sweep] {iid}: {type(e).__name__}: {e}")
    for s in db.collection("responders").where("availabilityStatus", "==", "Available").stream():
        seen_at = epoch(s.to_dict().get("lastSeenAt"))
        if seen_at is None or now - seen_at > C.STALE_OFFLINE_SECONDS:
            s.reference.update({"availabilityStatus": "Offline"})
    return sorted(seen)
