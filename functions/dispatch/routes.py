"""Google Routes API (server side). Only used for travel time and the route line. Every call is optional: if the key is missing or Google is slow,
the caller falls back to a straight-line estimate and the system keeps working. The key arrives as the environment variable MAPS_SERVER_KEY
(a Firebase secret). NEVER log the key."""
import json
import os
import html
import re
import urllib.request

MATRIX_URL = "https://routes.googleapis.com/distanceMatrix/v2:computeRouteMatrix"
ROUTE_URL = "https://routes.googleapis.com/directions/v2:computeRoutes"
TIMEOUT = 3.5


def _wp(lat, lng):
    return {"waypoint": {"location": {"latLng": {"latitude": float(lat), "longitude": float(lng)}}}}


def _secs(v):
    try:
        return float(str(v).rstrip("s"))
    except (TypeError, ValueError):
        return None


def _post(url, key, mask, body, http=None):
    if http is not None:
        return http(url, key, mask, body)
    req = urllib.request.Request(url, data=json.dumps(body).encode(), method="POST",
                                 headers={"Content-Type": "application/json", "X-Goog-Api-Key": key, "X-Goog-FieldMask": mask})
    with urllib.request.urlopen(req, timeout=TIMEOUT) as r:  # noqa: S310 - fixed https URL
        return json.loads(r.read().decode())


def matrix_seconds(key, origins, destinations, http=None):
    """origins/destinations: lists of (lat, lng). Returns {(i, j): seconds} for the pairs Google could route. {} on any failure."""
    if not key or not origins or not destinations or len(origins) * len(destinations) > 25:
        return {}
    try:
        body = {"origins": [_wp(*o) for o in origins], "destinations": [_wp(*d) for d in destinations], "travelMode": "DRIVE"}
        data = _post(MATRIX_URL, key, "originIndex,destinationIndex,duration,condition", body, http)
        out = {}
        for e in data if isinstance(data, list) else []:
            s = _secs(e.get("duration"))
            if s is not None and e.get("condition", "ROUTE_EXISTS") == "ROUTE_EXISTS":
                out[(int(e.get("originIndex", 0)), int(e.get("destinationIndex", 0)))] = s
        return out
    except Exception as e:  # noqa: BLE001 - never block an emergency because a map call failed
        print(f"[routes] matrix failed: {type(e).__name__}")
        return {}


# Turn-by-turn steps (only requested when the app asks for them, so ordinary route calls cost and return what they always did).
ROUTE_STEPS_MASK = (",routes.legs.steps.navigationInstruction,routes.legs.steps.distanceMeters,"
                    "routes.legs.steps.staticDuration,routes.legs.steps.polyline.encodedPolyline")
MAX_STEPS = 120
MAX_INSTRUCTION_CHARS = 120
_TAGS = re.compile(r"<[^>]*>")
_MANEUVERS = {
    "TURN_LEFT": "turn-left", "TURN_RIGHT": "turn-right", "TURN_SLIGHT_LEFT": "turn-slight-left", "TURN_SLIGHT_RIGHT": "turn-slight-right",
    "TURN_SHARP_LEFT": "turn-sharp-left", "TURN_SHARP_RIGHT": "turn-sharp-right", "UTURN_LEFT": "uturn-left", "UTURN_RIGHT": "uturn-right",
    "ROUNDABOUT_LEFT": "roundabout-left", "ROUNDABOUT_RIGHT": "roundabout-right", "RAMP_LEFT": "ramp-left", "RAMP_RIGHT": "ramp-right",
    "FORK_LEFT": "fork-left", "FORK_RIGHT": "fork-right", "KEEP_LEFT": "keep-left", "KEEP_RIGHT": "keep-right", "MERGE": "merge", "STRAIGHT": "straight",
}


def clean_instruction(text, limit=MAX_INSTRUCTION_CHARS):
    """Plain text for the turn banner: tags removed, entities decoded, spaces tidied, cut to `limit`."""
    t = html.unescape(_TAGS.sub(" ", str(text if text is not None else "")))
    return " ".join(t.split())[:limit]


def _num(v):
    return int(v) if isinstance(v, (int, float)) and not isinstance(v, bool) else None


def normalize_steps(legs):
    """Google's legs -> {"steps": [...up to 120...], "stepsTruncated": True when there were more (then no per-step lines)}. Never raises."""
    raw = []
    for leg in legs if isinstance(legs, list) else []:
        for st in (leg.get("steps") if isinstance(leg, dict) else None) or []:
            if isinstance(st, dict):
                raw.append(st)
    truncated = len(raw) > MAX_STEPS
    out = []
    for st in raw[:MAX_STEPS]:
        nav = st.get("navigationInstruction") if isinstance(st.get("navigationInstruction"), dict) else {}
        poly = st.get("polyline") if isinstance(st.get("polyline"), dict) else {}
        dur = _secs(st.get("staticDuration"))
        out.append({"instruction": clean_instruction(nav.get("instructions")), "maneuver": _MANEUVERS.get(nav.get("maneuver")),
                    "distanceM": _num(st.get("distanceMeters")), "durationSec": int(round(dur)) if dur is not None else None,
                    "polyline": None if truncated else (poly.get("encodedPolyline") or None)})
    res = {"steps": out}
    if truncated:
        res["stepsTruncated"] = True
    return res


def route(key, origin, dest, http=None, steps=False):
    """Returns {'polyline': str, 'durationS': float, 'distanceM': int} or None."""
    if not key:
        return None
    try:
        body = {"origin": _wp(*origin)["waypoint"], "destination": _wp(*dest)["waypoint"], "travelMode": "DRIVE"}
        mask = "routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline"
        if steps:
            mask += ROUTE_STEPS_MASK
            body["polylineQuality"] = "HIGH_QUALITY"
        data = _post(ROUTE_URL, key, mask, body, http)
        r = (data.get("routes") or [None])[0]
        if not r:
            return None
        out = {"polyline": (r.get("polyline") or {}).get("encodedPolyline", ""), "durationS": _secs(r.get("duration")) or 0.0, "distanceM": int(r.get("distanceMeters", 0))}
        if steps:
            out.update(normalize_steps(r.get("legs")))
        return out
    except Exception as e:  # noqa: BLE001
        print(f"[routes] route failed: {type(e).__name__}")
        return None


def key():
    """The secret may be the word "unset" when no server key has been created yet: then everything uses straight-line estimates."""
    k = os.environ.get("MAPS_SERVER_KEY", "").strip()
    return None if k.lower() in ("", "unset", "none", "placeholder") else k
