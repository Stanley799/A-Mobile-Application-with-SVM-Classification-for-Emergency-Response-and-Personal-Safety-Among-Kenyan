"""Phase 3A.2 callables (imported by main.py next to phase3_functions).
  help_geocode    : lat,lng -> street label for the "You are at ..." line (signed-in users)
  help_directions : origin,dest -> route line + minutes + km, drawn inside the app (signed-in users)
Both use the Firebase secret MAPS_SERVER_KEY; without it they answer ok:false / a straight-line estimate and the app still works."""
import math

from firebase_functions import https_fn, options

import dispatch  # noqa: F401
from dispatch import config as C, core, lookup, routes
from phase3_functions import MAPS_SERVER_KEY

OPTS = dict(region=C.REGION, memory=options.MemoryOption.MB_256, timeout_sec=20, max_instances=10, secrets=[MAPS_SERVER_KEY])


def _auth(req):
    if req.auth is None:
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.UNAUTHENTICATED, "Sign in first.")


def _pt(d, a, b):
    try:
        la, lo = float(d.get(a)), float(d.get(b))
    except (TypeError, ValueError):
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.INVALID_ARGUMENT, "Bad coordinates.")
    if not (math.isfinite(la) and math.isfinite(lo) and -90 <= la <= 90 and -180 <= lo <= 180):
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.INVALID_ARGUMENT, "Bad coordinates.")
    return la, lo


def directions(key, o, d, http=None):
    km = core.dl.haversine_km(o[0], o[1], d[0], d[1])
    r = routes.route(key, o, d, http)
    if r is None:
        return {"ok": True, "polyline": "", "etaS": round((2 + km * 1.35 / 25 * 60) * 60), "distanceM": round(km * 1000), "estimate": True}
    return {"ok": True, "polyline": r["polyline"], "etaS": r["durationS"], "distanceM": r["distanceM"], "estimate": False}


@https_fn.on_call(**OPTS)
def help_geocode(req: https_fn.CallableRequest):
    _auth(req)
    la, lo = _pt(req.data if isinstance(req.data, dict) else {}, "lat", "lng")
    g = lookup.reverse_geocode(routes.key(), la, lo)
    return {"ok": bool(g), "label": (g or {}).get("label", ""), "full": (g or {}).get("full", "")}


@https_fn.on_call(**OPTS)
def help_directions(req: https_fn.CallableRequest):
    _auth(req)
    d = req.data if isinstance(req.data, dict) else {}
    return directions(routes.key(), _pt(d, "fromLat", "fromLng"), _pt(d, "toLat", "toLng"))
