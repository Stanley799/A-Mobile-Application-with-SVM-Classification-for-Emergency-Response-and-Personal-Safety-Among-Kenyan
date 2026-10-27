"""Google Places / Geocoding lookups (server side, optional). Two jobs:
  1. wanted_types(): which kinds of place suit each emergency category, so EVERY category always has something to show.
  2. places_nearby(): when our own directory has too little near the resident, ask Google for the nearest hospital / police / fire / ambulance.
Results are used for ~10 minutes and shown on a Google map; they are not copied into our directory. reverse_geocode(): "Waiyaki Way, Westlands".
No key (MAPS_SERVER_KEY unset) -> every function returns empty and the system carries on with the directory only. NEVER log the key."""
import json
import urllib.parse
import urllib.request

TIMEOUT = 3.5
# Directory type names, best first. Used when the incident's roles give no types (e.g. "Other / General") and as the guaranteed minimum.
CATEGORY_TYPES = {
    "Medical Emergency": ["ambulance_operator", "hospital"],
    "Road Accident": ["ambulance_operator", "hospital", "police"],
    "Fire & Rescue": ["fire", "ambulance_operator", "hospital"],
    "Security Threat": ["police"],
    "Abduction": ["police"],
    "Other / General": ["hospital", "police", "ambulance_operator"],
}
SUBTYPE_TYPES = {
    "sexual_violence": ["hospital", "helpline"], "domestic_violence": ["helpline", "hospital", "police"],
    "mental_health_crisis": ["hospital", "ambulance_operator", "helpline"], "snakebite_or_poison": ["hospital", "ambulance_operator"],
    "emotional_distress": ["helpline"],
}
GOOGLE = {"hospital": ("nearby", "hospital"), "police": ("nearby", "police"), "fire": ("nearby", "fire_station"),
          "clinic": ("nearby", "doctor"), "ambulance_operator": ("text", "ambulance service")}
FIELDS = "places.id,places.displayName,places.location,places.formattedAddress,places.nationalPhoneNumber"


def wanted_types(category, subtype=None):
    if subtype in SUBTYPE_TYPES:
        return list(SUBTYPE_TYPES[subtype])
    return list(CATEGORY_TYPES.get(category, CATEGORY_TYPES["Other / General"]))


def _json(url, headers, body=None, http=None):
    if http is not None:
        return http(url, headers, body)
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, headers=headers, method="POST" if body is not None else "GET")
    with urllib.request.urlopen(req, timeout=TIMEOUT) as r:  # noqa: S310 - fixed https URLs
        return json.loads(r.read().decode())


def places_nearby(key, lat, lng, dtype, radius_m=8000, http=None):
    """Up to 5 nearest places of one directory type, as directory-shaped dicts. [] on any failure."""
    if not key or dtype not in GOOGLE:
        return []
    mode, term = GOOGLE[dtype]
    circle = {"center": {"latitude": float(lat), "longitude": float(lng)}, "radius": float(radius_m)}
    headers = {"Content-Type": "application/json", "X-Goog-Api-Key": key, "X-Goog-FieldMask": FIELDS}
    try:
        if mode == "nearby":
            body = {"includedTypes": [term], "maxResultCount": 5, "rankPreference": "DISTANCE", "locationRestriction": {"circle": circle}}
            data = _json("https://places.googleapis.com/v1/places:searchNearby", headers, body, http)
        else:
            body = {"textQuery": term, "maxResultCount": 5, "locationBias": {"circle": circle}}
            data = _json("https://places.googleapis.com/v1/places:searchText", headers, body, http)
    except Exception as e:  # noqa: BLE001 - a failed lookup must never block an emergency
        print(f"[lookup] places failed: {type(e).__name__}")
        return []
    out = []
    for p in (data or {}).get("places") or []:
        loc = p.get("location") or {}
        name = (p.get("displayName") or {}).get("text", "")
        if not p.get("id") or not name or "latitude" not in loc or "longitude" not in loc:
            continue
        phone = p.get("nationalPhoneNumber") or ""
        out.append({"id": "g_" + p["id"], "name": name, "type": dtype, "lat": float(loc["latitude"]), "lng": float(loc["longitude"]),
                    "phones": [phone] if phone else [], "address": p.get("formattedAddress", ""), "verified": False, "status": "active",
                    "is24h": None, "source": "google"})
    return out


def reverse_geocode(key, lat, lng, http=None):
    """{'label': 'Waiyaki Way, Westlands', 'full': '...'} or None."""
    if not key:
        return None
    q = urllib.parse.urlencode({"latlng": f"{float(lat):.6f},{float(lng):.6f}", "key": key, "result_type": "street_address|route|neighborhood|sublocality"})
    try:
        data = _json("https://maps.googleapis.com/maps/api/geocode/json?" + q, {}, None, http)
    except Exception as e:  # noqa: BLE001
        print(f"[lookup] geocode failed: {type(e).__name__}")
        return None
    res = (data or {}).get("results") or []
    if not res:
        return None
    comps = res[0].get("address_components") or []

    def pick(*kinds):
        for k in kinds:
            for c in comps:
                if k in (c.get("types") or []):
                    return c.get("long_name", "")
        return ""
    road = pick("route")
    area = pick("neighborhood", "sublocality", "sublocality_level_1", "locality")
    label = ", ".join(x for x in (road, area) if x) or ",".join(res[0].get("formatted_address", "").split(",")[:2]).strip()
    return {"label": label, "full": res[0].get("formatted_address", "")} if label else None
