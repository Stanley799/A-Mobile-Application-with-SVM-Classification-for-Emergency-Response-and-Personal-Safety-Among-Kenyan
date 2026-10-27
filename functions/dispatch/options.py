"""PURE ranking of the (at most 3) help options the resident sees. No Firestore, no network: everything comes in as plain data, so it is fully tested.
Option kinds:  live    = a registered responder (can accept, can be tracked once accepted)
               place   = a real facility with coordinates from the directory (call / directions only)
               hotline = a directory entry without coordinates (ambulance operator, helpline): call only
Weights (tunable in WEIGHTS, to be reviewed with an EMS practitioner):  score = .55 ETA + .20 fit + .15 reliability + .10 verified."""
from . import config as C
from . import core
from . import lookup

WEIGHTS = {"eta": 0.55, "fit": 0.20, "reliability": 0.15, "verified": 0.10}
ETA_CAP_MIN = 45.0           # an ETA of this or more scores 0
ROAD_FACTOR = 1.35           # straight line -> road distance
LIVE_KMH, PLACE_KMH, BASE_MIN = 30.0, 25.0, 2.0
HOTLINE_SCORE = 0.30         # call-only entries sit behind close options but ahead of far ones
LIVE_FAR_MIN = 10.0          # if the best live unit is further than this, one call-able place is guaranteed a slot
TYPES_FOR_ROLE = {
    "medical_transport": ("hospital", "clinic", "ambulance_operator"), "maternal_care": ("hospital",), "gbv_care": ("hospital", "clinic", "helpline"),
    "antivenom": ("hospital",), "fire_suppression": ("fire",), "extrication": ("fire",), "law_enforcement": ("police",),
}
TYPE_FIT = {"hospital": 1.0, "ambulance_operator": 1.0, "fire": 1.0, "police": 1.0, "helpline": 0.8, "clinic": 0.5, "other": 0.3}
CAP_WORDS = {"medical_transport": "Ambulance", "fire_suppression": "Fire", "extrication": "Cutting free", "law_enforcement": "Police",
             "maternal_care": "Maternal care", "gbv_care": "GBV care", "antivenom": "Antivenom"}
FAILED = ("declined", "expired")
HELD = ("accepted", "enroute", "arrived")


def estimate_minutes(km, kmh):
    return round(BASE_MIN + (km * ROAD_FACTOR / kmh) * 60.0, 1)


def _eta_fit(minutes):
    return max(0.0, 1.0 - min(minutes, ETA_CAP_MIN) / ETA_CAP_MIN)


def _score(eta_min, fit, reliability, verified):
    return round(WEIGHTS["eta"] * (_eta_fit(eta_min) if eta_min is not None else 0.0) + WEIGHTS["fit"] * fit +
                 WEIGHTS["reliability"] * reliability + WEIGHTS["verified"] * (1.0 if verified else 0.0), 4)


def _types(required, preferred):
    out = []
    for r in list(required) + [p for p in preferred if p not in required]:
        for t in TYPES_FOR_ROLE.get(r, ()):
            if t not in out:
                out.append(t)
    return out


def _live_fit(caps, required, preferred):
    req = len(set(caps) & set(required)) / len(required) if required else 0.7
    pref = (len(set(caps) & set(preferred)) / len(preferred)) if preferred else 0.0
    return min(1.0, 0.8 * req + 0.2 * pref) if required else min(1.0, 0.7 + 0.3 * pref)


def _place_fit(f, required, preferred):
    t = f.get("type", "other")
    served = [r for r in required if t in TYPES_FOR_ROLE.get(r, ())]
    base = (len(served) / len(required)) if required else (0.5 if t in _types(required, preferred) else 0.2)
    fit = base * TYPE_FIT.get(t, 0.3)
    wanted = set(required) | set(preferred)
    fit += 0.1 * len(set(f.get("services") or []) & wanted)
    return min(1.0, fit)


def _why(parts):
    return [p for p in parts if p]


def _serves(c, role):
    if c["kind"] == "live":
        return role in (c.get("caps") or [])
    return c.get("orgType") in TYPES_FOR_ROLE.get(role, ())


def _diversify(cands, required, n):
    """Best candidate for each needed role first (so a road accident gets help for the injured AND police, not three hospitals), then fill by score.
    Never more than 2 of the same kind. cands must already be sorted best first."""
    top = []
    for role in required:
        pick = next((c for c in cands if c not in top and _serves(c, role)), None)
        if pick is not None and len(top) < n:
            top.append(pick)
    for c in cands:
        if len(top) >= n:
            break
        if c not in top and sum(1 for t in top if t.get("orgType") == c.get("orgType")) < 2:
            top.append(c)
    for c in cands:                                                   # still short (e.g. only one kind exists): allow repeats
        if len(top) >= n:
            break
        if c not in top:
            top.append(c)
    return top


def build(inc, priority, avail, assigned, offers, facilities, state, now, minutes=None):
    """inc: incident view (lat/lng/category/subtype). avail: responder views that are Available. assigned: responder views that hold an accepted job.
    offers: this incident's offers. facilities: directory docs (dicts with id). minutes: optional {refId: (minutes, 'road')} from the routing service.
    Returns (options, meta). options is a list of 0..3 dicts sorted best first."""
    minutes = minutes or {}
    required, preferred, _n = core.needs(inc)
    lat, lng = inc["lat"], inc["lng"]
    by_resp = {}
    for o in offers:
        by_resp.setdefault(o["responderId"], []).append(o)
    failed = [o for o in offers if o["status"] in FAILED]
    failed_ids = {o["responderId"] for o in failed} | {o["responderId"] for o in offers if o["status"] == "withdrawn"}
    cands = []

    # ---- live units: ones that hold the job, then available ones that could still be asked
    for r in assigned:
        mine = by_resp.get(r["id"], [])
        st = next((o["status"] for o in mine if o["status"] in HELD), None)
        if not st:
            continue
        km = core.dl.haversine_km(lat, lng, r["lat"], r["lng"]) if r.get("lat") is not None else None
        eta = minutes.get(r["id"], (estimate_minutes(km, LIVE_KMH) if km is not None else None, "estimate"))
        caps = core.effective_caps(r)
        cands.append({"kind": "live", "refId": r["id"], "name": r["name"], "orgType": r.get("type"), "lat": r.get("lat"), "lng": r.get("lng"),
                      "distanceKm": round(km, 2) if km is not None else None, "etaMin": eta[0], "etaSource": eta[1], "status": st, "phone": r.get("phone", ""),
                      "caps": sorted(set(caps) & set(required + preferred)), "score": 9.0, "why": ["On the way to you" if st == "enroute" else "Accepted your request"]})
    held_ids = {c["refId"] for c in cands}
    radius = core.R["max_radius_km"][priority]
    seen = set()
    for role in (required or [None]):
        for r in core.rank_candidates({"lat": lat, "lng": lng}, avail, role, preferred, now, priority, failed_ids | held_ids):
            if r["id"] in seen:
                continue
            seen.add(r["id"])
            mine = by_resp.get(r["id"], [])
            asked = any(o["status"] == "offered" for o in mine)
            eta = minutes.get(r["id"], (estimate_minutes(r["distance_km"], LIVE_KMH), "estimate"))
            fit = _live_fit(r["caps"], required, preferred)
            rel = min(1.0, 0.5 * float(r.get("accept_rate", 0.6)) + 0.1 * float(r.get("rating", 3.0)))
            cands.append({"kind": "live", "refId": r["id"], "name": r["name"], "orgType": r.get("type"), "lat": r["lat"], "lng": r["lng"],
                          "distanceKm": r["distance_km"], "etaMin": eta[0], "etaSource": eta[1], "status": "asking" if asked else "available", "phone": "",
                          "caps": sorted(set(r["caps"]) & set(required + preferred)), "score": _score(eta[0], fit, rel, True) + 0.05,
                          "why": _why(["Registered unit, can be tracked live", "Being asked now" if asked else "Available"])})

    # ---- directory places and call-only entries
    gbv = inc.get("subtype") in ("sexual_violence", "domestic_violence") or "gbv_care" in (required + preferred)
    types = _types(required, preferred + (["gbv_care"] if gbv else []))
    for t in lookup.wanted_types(inc.get("category"), inc.get("subtype")):   # every category always has suitable kinds, even with no roles ("Other")
        if t not in types:
            types.append(t)
    if not held_ids or len(held_ids) < 3:
        for f in facilities:
            if f.get("status", "active") != "active" or f.get("type") not in types and f.get("type") != "helpline":
                continue
            if f.get("type") == "helpline" and not gbv:
                continue
            if f.get("linkedResponderId") and f["linkedResponderId"] in (seen | held_ids | failed_ids):
                continue                                              # already shown as the live unit: one card, not two
            verified = bool(f.get("verified"))
            fit = _place_fit(f, required, preferred)
            if f.get("lat") is None or f.get("lng") is None:
                if not f.get("phones"):
                    continue
                cands.append({"kind": "hotline", "refId": f["id"], "name": f.get("name", ""), "orgType": f.get("type"), "lat": None, "lng": None, "distanceKm": None,
                              "etaMin": None, "etaSource": None, "status": "call", "phone": (f.get("phones") or [""])[0], "phones": f.get("phones") or [],
                              "is24h": f.get("is24h"), "verified": verified, "caps": [], "score": HOTLINE_SCORE * (0.5 + 0.5 * fit) + (0.05 if verified else 0.0),
                              "why": _why(["Call-only service", "Hours not verified" if f.get("is24h") is None else ("Open 24 hours" if f.get("is24h") else "")])})
                continue
            km = core.dl.haversine_km(lat, lng, f["lat"], f["lng"])
            if km > radius:
                continue
            eta = minutes.get(f["id"], (estimate_minutes(km, PLACE_KMH), "estimate"))
            cands.append({"kind": "place", "refId": f["id"], "name": f.get("name", ""), "orgType": f.get("type"), "lat": f["lat"], "lng": f["lng"], "distanceKm": round(km, 2),
                          "etaMin": eta[0], "etaSource": eta[1], "status": "directions", "phone": (f.get("phones") or [""])[0], "phones": f.get("phones") or [],
                          "is24h": f.get("is24h"), "address": f.get("address", ""), "verified": verified, "caps": [], "source": f.get("source") or "directory",
                          "score": _score(eta[0], fit, 0.5, verified),
                          "why": _why(["Open 24 hours" if f.get("is24h") else "Call to confirm it is open", "Found on Google Maps" if f.get("source") == "google" else ("" if verified else "Phone not yet verified")])})

    # ---- choose at most 3
    cands.sort(key=lambda c: (-c["score"], c["etaMin"] if c["etaMin"] is not None else 999, c["refId"]))
    top = _diversify(cands, required, 3)
    lives = [c for c in cands if c["kind"] == "live"]
    if lives and not any(c["kind"] == "live" for c in top):
        top = top[:2] + [lives[0]]                                    # a unit that can actually come always gets a slot
    best_live = min([c["etaMin"] for c in top if c["kind"] == "live" and c["etaMin"] is not None] or [None], default=None) if any(c["kind"] == "live" for c in top) else None
    callable_ = [c for c in cands if c["kind"] != "live"]
    if callable_ and not any(c["kind"] != "live" for c in top) and (best_live is None or best_live > LIVE_FAR_MIN) and not held_ids:
        top = top[:2] + [callable_[0]]                                # far or no unit: guarantee something callable in seconds
    top.sort(key=lambda c: (-c["score"], c["refId"]))
    for i, c in enumerate(top, 1):
        c["rank"] = i
        c.pop("score", None)
    n_failed = len(failed)
    held = bool(held_ids)
    asking = [c["name"] for c in top if c["kind"] == "live" and c["status"] == "asking"]
    meta = {"mode": "map", "sensitive": inc.get("subtype") in ("sexual_violence", "domestic_violence"), "state": state, "failedCount": n_failed, "asking": asking, "held": held,
            "suggestCall": (n_failed >= 2 and not held) or (not any(c["kind"] == "live" for c in top) and not held),
            "showNumbers": (n_failed >= 3 and not held) or state in ("unfilled", "no_location"),
            "noLive": not lives}
    return top, meta


def helplines_only(state):
    return [], {"mode": "helplines", "sensitive": False, "state": state, "failedCount": 0, "asking": [], "held": False, "suggestCall": False, "showNumbers": True, "noLive": True}
