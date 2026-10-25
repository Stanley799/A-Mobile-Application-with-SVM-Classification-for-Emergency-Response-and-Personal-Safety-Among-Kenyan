"""Route line + ETA for one accepted unit -> the incident, cached so the Routes API is called rarely."""
from . import core, routes, store

CACHE_FRESH_S, CACHE_MAX_S, MOVED_M = 30, 180, 150


def route_for(db, incident_id, responder_id, uid, is_admin, now, key=None, http=None):
    isnap = db.collection("incidents").document(incident_id).get()
    if not isnap.exists:
        return {"ok": False, "reason": "not_found"}
    inc = store.incident_view(incident_id, isnap.to_dict())
    if not (is_admin or uid == inc["userId"] or uid == responder_id):
        return {"ok": False, "reason": "forbidden"}
    offer = db.collection("offers").document(f"{incident_id}_{responder_id}").get()
    if not offer.exists or offer.to_dict().get("status") not in ("accepted", "enroute", "arrived") or inc["lat"] is None:
        return {"ok": False, "reason": "not_assigned"}
    tr = db.collection("incidents").document(incident_id).collection("tracks").document(responder_id).get()
    pos = tr.to_dict() if tr.exists else None
    if pos is None:
        rs = db.collection("responders").document(responder_id).get()
        r = rs.to_dict() if rs.exists else {}
        pos = {"lat": r.get("currentLatitude"), "lng": r.get("currentLongitude")}
    if pos.get("lat") is None:
        return {"ok": False, "reason": "no_position"}
    cache_ref = db.collection("incidents").document(incident_id).collection("routes").document(responder_id)
    c = cache_ref.get()
    cd = c.to_dict() if c.exists else None
    if cd:
        age = now - (store.epoch(cd.get("at")) or 0)
        moved = core.dl.haversine_km(pos["lat"], pos["lng"], cd["fromLat"], cd["fromLng"]) * 1000
        if age < CACHE_FRESH_S or (age < CACHE_MAX_S and moved < MOVED_M):
            return {"ok": True, "polyline": cd["polyline"], "etaS": cd["etaS"], "distanceM": cd["distanceM"], "ageS": round(age), "cached": True}
    r = routes.route(key if key is not None else routes.key(), (pos["lat"], pos["lng"]), (inc["lat"], inc["lng"]), http)
    if r is None:
        km = core.dl.haversine_km(pos["lat"], pos["lng"], inc["lat"], inc["lng"])
        return {"ok": True, "polyline": "", "etaS": round((2 + km * 1.35 / 30 * 60) * 60), "distanceM": round(km * 1000), "estimate": True}
    cache_ref.set({"polyline": r["polyline"], "etaS": r["durationS"], "distanceM": r["distanceM"], "fromLat": pos["lat"], "fromLng": pos["lng"], "at": store.when(now)})
    return {"ok": True, "polyline": r["polyline"], "etaS": r["durationS"], "distanceM": r["distanceM"], "cached": False}
