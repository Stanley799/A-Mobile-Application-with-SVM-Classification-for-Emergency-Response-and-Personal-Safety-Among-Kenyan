"""Firestore side of the help options: reads the directory, asks the routing service for travel times (optional), writes
incidents/{id}/options/r1..r3 and options/meta, and removes live-location tracks of units that no longer hold the job.
Failure here must NEVER stop dispatch: store.reconcile_incident calls refresh() inside try/except."""
import math

from google.cloud.firestore import SERVER_TIMESTAMP

from . import config as C
from . import core, options, routes, store

ETA_REUSE_SECONDS = 90
SUBCOLS = ("r1", "r2", "r3")


def facilities_near(db, lat, lng, radius_km):
    """The directory is small (one city), so: a latitude band from Firestore, then exact distance in code. No composite index needed."""
    dlat = radius_km / 111.0
    out = []
    q = db.collection("facilities").where("lat", ">=", lat - dlat).where("lat", "<=", lat + dlat)
    for s in q.stream():
        d = s.to_dict() or {}
        out.append({**d, "id": s.id})
    out += [{**(s.to_dict() or {}), "id": s.id} for s in db.collection("facilities").where("kind", "==", "hotline").stream()]
    seen, uniq = set(), []
    for f in out:
        if f["id"] not in seen:
            seen.add(f["id"]); uniq.append(f)
    return uniq


def _read_old(db, iid):
    col = db.collection("incidents").document(iid).collection("options")
    old = {}
    for rid in SUBCOLS:
        s = col.document(rid).get()
        if s.exists:
            old[rid] = s.to_dict()
    return old


def _eta_minutes(db, key, inc, avail, assigned, facilities, now, old):
    """Road travel times for the best few candidates only (<= 6 elements per incident). Falls back to estimates by returning {}."""
    if not key:
        return {}
    reuse = {}
    for o in old.values():
        at = store.epoch(o.get("etaAt"))
        if o.get("etaSource") == "road" and at and now - at < ETA_REUSE_SECONDS:
            reuse[o["refId"]] = (o["etaMin"], "road")
    lat, lng = inc["lat"], inc["lng"]
    units = sorted([r for r in avail + assigned if r.get("lat") is not None], key=lambda r: core.dl.haversine_km(lat, lng, r["lat"], r["lng"]))[:3]
    places = sorted([f for f in facilities if f.get("lat") is not None and f.get("status", "active") == "active"],
                    key=lambda f: core.dl.haversine_km(lat, lng, f["lat"], f["lng"]))[:3]
    out = dict(reuse)
    need_u = [u for u in units if u["id"] not in reuse]
    if need_u:
        m = routes.matrix_seconds(key, [(u["lat"], u["lng"]) for u in need_u], [(lat, lng)])
        for (i, _j), sec in m.items():
            out[need_u[i]["id"]] = (round(sec / 60.0, 1), "road")
    need_p = [f for f in places if f["id"] not in reuse]
    if need_p:
        m = routes.matrix_seconds(key, [(lat, lng)], [(f["lat"], f["lng"]) for f in need_p])
        for (_i, j), sec in m.items():
            out[need_p[j]["id"]] = (round(sec / 60.0, 1), "road")
    return out


def _doc(c, now_marker=True):
    d = {k: v for k, v in c.items() if v is not None}
    d["etaAt"] = SERVER_TIMESTAMP
    d["updatedAt"] = SERVER_TIMESTAMP
    return d


def _same(a, b):
    ignore = ("etaAt", "updatedAt")
    return {k: v for k, v in (a or {}).items() if k not in ignore} == {k: v for k, v in (b or {}).items() if k not in ignore}


def refresh(db, iid, inc, dispatch, now, key=None):
    """Recompute and store the options for one incident. `dispatch` is the dispatch summary just computed (state, escalate922)."""
    state = dispatch.get("state")
    col = db.collection("incidents").document(iid).collection("options")
    if state in ("cancelled", "completed") or inc.get("status") not in ("Active", "SupportOnly", "Resolved"):
        _clear(col); _prune_tracks(db, iid, {}); return
    if state in ("support_only",):
        opts, meta = options.helplines_only(state)
    elif inc.get("lat") is None or inc.get("lng") is None or state in ("awaiting_details", "needs_review"):
        opts, meta = [], {"mode": "map", "sensitive": inc.get("subtype") in ("sexual_violence", "domestic_violence"), "state": state, "failedCount": 0, "asking": [], "held": False, "suggestCall": False,
                          "showNumbers": state in ("no_location",) or bool(dispatch.get("escalate922")), "noLive": True}
    else:
        offers = store.offers_for(db, iid)
        pr = core.server_priority(inc, store.table())["priority"]
        avail = store.available_responders(db)
        held_ids = [o["responderId"] for o in offers if o["status"] in options.HELD]
        assigned = []
        for rid in held_ids:
            s = db.collection("responders").document(rid).get()
            if s.exists:
                assigned.append(store.responder_view(db, rid, s.to_dict()))
        facilities = facilities_near(db, inc["lat"], inc["lng"], core.R["max_radius_km"][pr])
        old = _read_old(db, iid)
        minutes = _eta_minutes(db, key if key is not None else routes.key(), inc, avail, assigned, facilities, now, old)
        opts, meta = options.build(inc, pr, avail, assigned, offers, facilities, state, now, minutes)
        if dispatch.get("escalate922"):
            meta["showNumbers"] = True
        _prune_tracks(db, iid, {o["responderId"] for o in offers if o["status"] in options.HELD})
    old = _read_old(db, iid)
    want = {f"r{c['rank']}": c for c in opts}
    for rid in SUBCOLS:
        if rid in want:
            if not _same(old.get(rid), _plain(want[rid])):
                col.document(rid).set(_doc(want[rid]))
        elif rid in old:
            col.document(rid).delete()
    cur = col.document("meta").get()
    if not cur.exists or not _same(cur.to_dict(), meta):
        col.document("meta").set({**meta, "updatedAt": SERVER_TIMESTAMP})


def _plain(c):
    return {k: v for k, v in c.items() if v is not None}


def _clear(col):
    for rid in SUBCOLS + ("meta",):
        col.document(rid).delete()


def _prune_tracks(db, iid, keep_ids):
    """Live-location privacy: a unit's track exists only while it holds the job."""
    col = db.collection("incidents").document(iid).collection("tracks")
    for s in col.stream():
        if s.id not in keep_ids:
            s.reference.delete()
