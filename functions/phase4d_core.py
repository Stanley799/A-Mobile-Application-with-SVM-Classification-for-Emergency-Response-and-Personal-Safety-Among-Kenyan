"""Phase 4D backbone. Server-only writes and the small pure decisions behind them:
  events      : an append-only per-incident record (who did what, when) written only by Cloud Functions
  attention   : an incident that has waited too long, needs more units or raised an SOS is flagged for a human
  metrics     : the response-time numbers of one incident, written once when it closes
Planning (dispatch/core.py, dispatch/options.py) is NOT touched here.
"""
import datetime as dt
import time

from google.api_core.exceptions import AlreadyExists
from google.cloud.firestore import SERVER_TIMESTAMP

from dispatch import config as C

# Targets chosen by us, inspired by NFPA 1221 call-processing benchmarks (90% within 64 s); tunable.
# Seconds after the FIRST offer, for an incident that still has no accepted unit.
ATTENTION_SECONDS = {"High": 60, "Medium": 120, "Low": 300}

# Reasons a human has to look. "none" means nothing is wrong.
ATTENTION_REASONS = ("no_accept_in_time", "extra_resources", "responder_sos", "low_accuracy", "none")

LOW_ACCURACY_M = 150          # above this the resident is asked for a landmark and the administrator sees it
SOS_COOLDOWN_SECONDS = 60

EVENT_TYPES = (
    "incident_created", "classified", "priority_set", "offer_sent", "offer_seen", "offer_accepted",
    "offer_declined", "offer_expired", "offer_withdrawn", "unit_en_route", "unit_arrived",
    "transport_started", "transport_arrived", "extra_resources_requested", "admin_assigned",
    "admin_revealed_contact", "attention_raised",
    "responder_sos", "incident_cancelled", "incident_closed",
)

ACTOR_ROLES = ("system", "resident", "responder", "admin")
OPEN_STATUSES = ("Active", "SupportOnly")
HELD = ("accepted", "enroute", "arrived", "completed")


class Phase4DError(Exception):
    """A refusal that the callable turns into a plain HttpsError (same pattern as resident_requests.RequestError)."""

    def __init__(self, code, message):
        super().__init__(message)
        self.code, self.message = code, message


def _epoch(v):
    if isinstance(v, (int, float)):
        return float(v)
    if isinstance(v, dt.datetime):
        return (v if v.tzinfo else v.replace(tzinfo=dt.timezone.utc)).timestamp()
    return None


def _clean_data(d):
    """Events carry ids and codes only: at most 8 keys, scalar values, short strings, no coordinates."""
    out = {}
    for k, v in (d or {}).items():
        if len(out) >= 8:
            break
        if isinstance(v, str):
            out[str(k)[:20]] = v[:60]
        elif isinstance(v, (bool, int, float)):
            out[str(k)[:20]] = v
    return out


def write_event(db, incident_id, event_type, actor_role, actor_id, data=None, event_id=None):
    """Create one event. The id is deterministic when the caller passes one, so a retried trigger cannot duplicate it."""
    if event_type not in EVENT_TYPES:
        raise ValueError(f"unknown event type {event_type}")
    if actor_role not in ACTOR_ROLES:
        raise ValueError(f"unknown actor role {actor_role}")
    ref = db.collection("incidents").document(incident_id).collection("events").document(event_id or event_type)
    try:
        ref.create({"type": event_type, "at": SERVER_TIMESTAMP, "actorRole": actor_role,
                    "actorId": actor_id or "system", "data": _clean_data(data)})
        return True
    except AlreadyExists:
        return False


def event_times(db, incident_id):
    """{type: earliest epoch} for one incident. Missing types are simply absent."""
    out = {}
    for s in db.collection("incidents").document(incident_id).collection("events").stream():
        d = s.to_dict() or {}
        t, e = d.get("type"), _epoch(d.get("at"))
        if t in EVENT_TYPES and e is not None and (t not in out or e < out[t]):
            out[t] = e
    return out


def compute_metrics(created_at, times, closed_at):
    """The five published numbers. Any step that never happened stays None (the app shows "Not recorded").
      secondsToClassify       alert created      -> category and priority set
      secondsToFirstOffer     classified         -> first offer sent
      secondsToFirstAccept    first offer        -> first acceptance
      secondsToFirstArrival   alert created      -> first unit arrived
      secondsTotal            alert created      -> closed
    """
    def gap(a, b):
        if a is None or b is None or b < a:
            return None
        return int(round(b - a))

    classified = times.get("classified")
    first_offer = times.get("offer_sent")
    first_accept = times.get("offer_accepted")
    first_arrival = times.get("unit_arrived")
    return {
        "secondsToClassify": gap(created_at, classified),
        "secondsToFirstOffer": gap(classified, first_offer),
        "secondsToFirstAccept": gap(first_offer, first_accept),
        "secondsToFirstArrival": gap(created_at, first_arrival),
        "secondsTotal": gap(created_at, closed_at),
    }


def close_metrics(db, incident_id, doc, now):
    """Write metrics once, for a closed incident. Writing twice changes nothing."""
    if doc.get("metrics") is not None:
        return False
    times = event_times(db, incident_id)
    created = _epoch(doc.get("createdAt"))
    db.collection("incidents").document(incident_id).update({"metrics": compute_metrics(created, times, now)})
    return True


def offers_of(db, incident_id):
    out = []
    for s in db.collection("offers").where("incidentId", "==", incident_id).stream():
        out.append({**(s.to_dict() or {}), "id": s.id})
    return out


def attention_decision(doc, offers, now):
    """'no_accept_in_time' when an open incident has waited past its target with nobody holding it; else None."""
    if doc.get("status") not in OPEN_STATUSES:
        return None
    if any(o.get("status") in HELD for o in offers):
        return None
    priority = ((doc.get("dispatch") or {}).get("priority") or doc.get("priority") or "High")
    limit = ATTENTION_SECONDS.get(priority, ATTENTION_SECONDS["High"])
    first = [_epoch(o.get("createdAt")) for o in offers]
    first = [f for f in first if f is not None]
    if not first:
        return None
    return "no_accept_in_time" if now - min(first) >= limit else None


def raise_attention(db, incident_id, reason, detail=None):
    """Flag an open incident for a human, once per reason."""
    ref = db.collection("incidents").document(incident_id)
    snap = ref.get()
    if not snap.exists:
        return False
    doc = snap.to_dict() or {}
    if doc.get("status") not in OPEN_STATUSES:
        return False
    if doc.get("needsAttention") is True and doc.get("attentionReason") == reason:
        return False
    ref.update({"needsAttention": True, "attentionReason": reason})
    write_event(db, incident_id, "attention_raised", "system", "system", {"reason": reason, **(detail or {})},
                f"attention_raised_{reason}")
    return True


def event_for_status(status, reason):
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


def stamp_offer_times(db, offer_id, new):
    """The phone keeps only the latest response time; stamp each status once so the completion summary has real timings."""
    status = new.get("status")
    if status not in ("accepted", "enroute", "arrived", "completed"):
        return
    if status in (new.get("offerTimes") or {}):
        return
    db.collection("offers").document(offer_id).update({f"offerTimes.{status}": SERVER_TIMESTAMP})


def record_offer_events(db, offer_id, new, old):
    """Events for one offer change. Deterministic ids: a retried trigger cannot duplicate an event."""
    iid = new.get("incidentId")
    if not iid:
        return
    if old is None:
        write_event(db, iid, "offer_sent", "system", "system",
                    {"role": new.get("role"), "wave": new.get("wave")}, f"offer_sent_{offer_id}")
        return
    stamp_offer_times(db, offer_id, new)
    rid = new.get("responderId")
    if old.get("seenAt") is None and new.get("seenAt") is not None:
        write_event(db, iid, "offer_seen", "responder", rid, {}, f"offer_seen_{offer_id}")
    if old.get("moreUnits") is None and isinstance(new.get("moreUnits"), dict):
        mu = new["moreUnits"]
        write_event(db, iid, "extra_resources_requested", "responder", rid,
                    {"role": mu.get("role"), "count": mu.get("count")}, f"extra_resources_requested_{offer_id}")
        # The planner derives roles from triage only. Without a planner change the request cannot add a
        # role, so the incident is flagged for an administrator instead (see the Phase 4D fix report).
        raise_attention(db, iid, "extra_resources")
    t_old, t_new = old.get("transport"), new.get("transport")
    if t_old is None and isinstance(t_new, dict):
        write_event(db, iid, "transport_started", "responder", rid,
                    {"destinationId": t_new.get("destinationId")}, f"transport_started_{offer_id}")
    elif isinstance(t_new, dict) and (t_old or {}).get("arrivedAt") is None and t_new.get("arrivedAt") is not None:
        write_event(db, iid, "transport_arrived", "responder", rid, {}, f"transport_arrived_{offer_id}")
    if old.get("status") != new.get("status"):
        etype, who = event_for_status(new.get("status"), new.get("withdrawReason"))
        if etype:
            write_event(db, iid, etype, who, rid if who == "responder" else "system",
                        {"role": new.get("role")}, f"{etype}_{offer_id}")


def sweep_attention(db, now):
    """Called from sweep_dispatch. Raises the SLA flag and clears it once a unit holds the incident.
    Another reason (extra units, SOS) is only cleared when that reason is resolved."""
    changed = []
    for s in db.collection("incidents").where("status", "==", "Active").stream():
        doc = s.to_dict() or {}
        reason = attention_decision(doc, offers_of(db, s.id), now)
        if reason and doc.get("needsAttention") is not True:
            if raise_attention(db, s.id, reason):
                changed.append(s.id)
        elif reason is None and doc.get("needsAttention") is True and doc.get("attentionReason") in ("no_accept_in_time", "low_accuracy"):
            s.reference.update({"needsAttention": False, "attentionReason": "none"})
            changed.append(s.id)
    return changed


# ------------------------------------------------------------------ administrator actions (the callables wrap these)

def admin_role(token):
    """('admin', uid) or Phase4DError. Administrators only."""
    role = (token or {}).get("role")
    uid = (token or {}).get("uid") or (token or {}).get("user_id")
    if role == "SystemAdmin":
        return "admin", uid
    raise Phase4DError("permission-denied", "Administrators only.")


def _open_incident(db, incident_id):
    snap = db.collection("incidents").document(incident_id).get()
    if not snap.exists:
        raise Phase4DError("not-found", "Incident not found.")
    doc = snap.to_dict() or {}
    if doc.get("status") not in OPEN_STATUSES:
        raise Phase4DError("failed-precondition", "That incident is already closed.")
    return doc


def _str(value, name, limit=128):
    if not isinstance(value, str) or not value or len(value) > limit or "/" in value:
        raise Phase4DError("invalid-argument", f"{name} is required.")
    return value


def sos_create(db, uid, incident_id, now):
    """A responder asks for immediate help. One per 60 s. Administrators see it."""
    rs = db.collection("responders").document(uid or "").get()
    if not rs.exists or (rs.to_dict() or {}).get("verificationStatus") != "Verified":
        raise Phase4DError("permission-denied", "Only a verified responder can raise an SOS.")
    for s in db.collection("sos_alerts").where("responderId", "==", uid).stream():
        d = s.to_dict() or {}
        at = _epoch(d.get("at"))
        if d.get("status") == "open" and at is not None and now - at < SOS_COOLDOWN_SECONDS:
            raise Phase4DError("resource-exhausted", "An SOS was just sent. Wait a minute.")
    r = rs.to_dict() or {}
    if incident_id:
        _open_incident(db, incident_id)
    sos_ref = db.collection("sos_alerts").document(f"{uid}_{int(now * 1000)}")
    sos_ref.create({"responderId": uid, "orgName": r.get("organizationName") or uid, "incidentId": incident_id or None,
                    "lat": r.get("currentLatitude"), "lng": r.get("currentLongitude"), "at": SERVER_TIMESTAMP, "status": "open"})
    if incident_id:
        raise_attention(db, incident_id, "responder_sos")
        write_event(db, incident_id, "responder_sos", "responder", uid, {"reason": "sos"}, f"responder_sos_{uid}_{int(now)}")
    return sos_ref.id


def resolve_sos(db, token, sos_id, note, now):
    role, uid = admin_role(token)
    note = (note or "")[:200]
    ref = db.collection("sos_alerts").document(_str(sos_id, "sosId"))
    snap = ref.get()
    if not snap.exists:
        raise Phase4DError("not-found", "SOS alert not found.")
    if (snap.to_dict() or {}).get("status") != "open":
        return False
    ref.update({"status": "resolved", "resolvedAt": SERVER_TIMESTAMP, "resolvedBy": uid, "note": note, "resolvedByRole": role})
    return True


def snapshot_contact(db, incident_id, incident):
    """Copies the caller's dispatch contact into a Functions-only document when the alert is created.
    Clients cannot read or write it (firestore.rules); reveal_contact and the post-acceptance release are the only paths."""
    uid = incident.get("userId")
    if not uid:
        return False
    ref = db.collection("incidents").document(incident_id).collection("private").document("contact")
    if ref.get().exists:
        return False
    u = db.collection("users").document(uid).get()
    ud = u.to_dict() if u.exists else {}
    ref.set({"userId": uid, "firstName": str(ud.get("firstName") or ""), "phone": str(ud.get("phoneNumber") or ""),
             "at": SERVER_TIMESTAMP})
    return True


def reveal_contact(db, token, incident_id):
    """Administrators only. Returns the caller's first name and phone, and records who looked."""
    role, uid = admin_role(token)
    doc = _open_incident_or_recent(db, incident_id)
    contact = db.collection("incidents").document(incident_id).collection("private").document("contact").get()
    c = (contact.to_dict() or {}) if contact.exists else {}
    first, phone = c.get("firstName", ""), c.get("phone", "")
    if not first and not phone:                 # older alert, or a profile that was not ready when it was created
        u = db.collection("users").document(doc.get("userId") or "").get()
        ud = u.to_dict() if u.exists else {}
        first, phone = ud.get("firstName", ""), ud.get("phoneNumber", "")
    write_event(db, incident_id, "admin_revealed_contact", role, uid, {"role": role}, f"admin_revealed_contact_{uid}_{int(time.time() * 1000)}")
    return {"firstName": first, "phone": phone}


def _open_incident_or_recent(db, incident_id):
    snap = db.collection("incidents").document(incident_id).get()
    if not snap.exists:
        raise Phase4DError("not-found", "Incident not found.")
    return snap.to_dict() or {}


