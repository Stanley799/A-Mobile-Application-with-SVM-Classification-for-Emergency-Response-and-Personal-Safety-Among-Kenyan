"""A resident asks one specific registered unit from their options list. Rules: it must be the resident's own active incident, the unit must be
in the incident's options and still available, it may not already hold or have refused this incident, and at most 3 such requests per incident."""
from . import config as C
from . import core
from . import store

MAX_RESIDENT_REQUESTS = 3


class RequestError(Exception):
    def __init__(self, code, message):
        super().__init__(message)
        self.code, self.message = code, message


def request_unit(db, incident_id, uid, responder_id, now):
    isnap = db.collection("incidents").document(incident_id).get()
    if not isnap.exists or isnap.to_dict().get("userId") != uid:
        raise RequestError("not-found", "Alert not found.")
    inc = store.incident_view(incident_id, isnap.to_dict())
    if inc["status"] != "Active" or inc["lat"] is None:
        raise RequestError("failed-precondition", "This alert is closed or has no location.")
    opt = None
    for rid in ("r1", "r2", "r3"):
        s = db.collection("incidents").document(incident_id).collection("options").document(rid).get()
        if s.exists and s.to_dict().get("kind") == "live" and s.to_dict().get("refId") == responder_id:
            opt = s.to_dict()
    if opt is None or opt.get("status") != "available":
        raise RequestError("failed-precondition", "That unit can no longer be requested. Choose another.")
    offers = store.offers_for(db, incident_id)
    if any(o["responderId"] == responder_id for o in offers):
        raise RequestError("failed-precondition", "That unit was already asked.")
    if len([o for o in offers if o.get("requestedBy") == "resident"]) >= MAX_RESIDENT_REQUESTS:
        raise RequestError("resource-exhausted", "You have already requested several units. Please wait or call 999.")
    rs = db.collection("responders").document(responder_id).get()
    if not rs.exists:
        raise RequestError("not-found", "Unit not found.")
    resp = store.responder_view(db, responder_id, rs.to_dict())
    if not resp["verified"] or resp["status"] != "available" or resp["lat"] is None or now - (resp["last_seen"] or 0) > core.R["heartbeat_max_age_seconds"]:
        raise RequestError("failed-precondition", "That unit is no longer available.")
    pr = core.server_priority(inc, store.table())
    required, preferred, n = core.needs(inc)
    caps = core.effective_caps(resp)
    role = next((r for r in required if r in caps), required[0] if required else "any_responder")
    covered = [o for o in offers if o["status"] in C.ACCEPTED_OFFER and (role == "any_responder" or role in (o.get("covers") or []) or o.get("role") == role)]
    if covered:
        raise RequestError("failed-precondition", "That need is already covered by a unit on the way.")
    dist = round(core.dl.haversine_km(inc["lat"], inc["lng"], resp["lat"], resp["lng"]), 2)
    offer = {"id": f"{incident_id}_{responder_id}", "incidentId": incident_id, "incidentCode": inc["code"], "responderId": responder_id, "role": role, "wave": 0,
             "status": "offered", "createdAt": now, "expiresAt": now + C.OFFER_SECONDS, "distanceKm": dist, "priority": pr["priority"], "category": inc["category"],
             "subtype": inc["subtype"], "covers": sorted(set(caps) & set(required + preferred)), "requestedBy": "resident",
             "location": {"lat": inc["lat"], "lng": inc["lng"]}, **core.briefing_fields(inc, pr["priority"], required, n or {})}
    created = store.apply_actions(db, [{"type": "create_offer", "offer": offer}])
    if not created:
        raise RequestError("failed-precondition", "That unit was already asked.")
    store.audit(db, "offer_requested_by_resident", incident_id, responderId=responder_id)
    return offer
