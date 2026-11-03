"""Google Routes API (server side). Only used for travel time and the route line. Every call is optional: if the key is missing or Google is slow,
the caller falls back to a straight-line estimate and the system keeps working. The key arrives as the environment variable MAPS_SERVER_KEY
(a Firebase secret). NEVER log the key."""
import json
import os
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


def route(key, origin, dest, http=None):
    """Returns {'polyline': str, 'durationS': float, 'distanceM': int} or None."""
    if not key:
        return None
    try:
        body = {"origin": _wp(*origin)["waypoint"], "destination": _wp(*dest)["waypoint"], "travelMode": "DRIVE"}
        data = _post(ROUTE_URL, key, "routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline", body, http)
        r = (data.get("routes") or [None])[0]
        if not r:
            return None
        return {"polyline": (r.get("polyline") or {}).get("encodedPolyline", ""), "durationS": _secs(r.get("duration")) or 0.0, "distanceM": int(r.get("distanceMeters", 0))}
    except Exception as e:  # noqa: BLE001
        print(f"[routes] route failed: {type(e).__name__}")
        return None


def key():
    """The secret may be the word "unset" when no server key has been created yet: then everything uses straight-line estimates."""
    k = os.environ.get("MAPS_SERVER_KEY", "").strip()
    return None if k.lower() in ("", "unset", "none", "placeholder") else k
