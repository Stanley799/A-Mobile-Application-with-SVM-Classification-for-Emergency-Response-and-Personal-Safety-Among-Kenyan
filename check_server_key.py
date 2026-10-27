"""Checks that the Google SERVER key works for the three APIs the system uses: Geocoding (street name), Places (nearby facilities), Routes (road minutes).
Run from C:\\EmergencyResponseSystem:   py tools\\check_server_key.py
It asks for the key with hidden typing (or reads the environment variable MAPS_SERVER_KEY). The key is never printed or saved.
For each API it prints PASS, or FAIL with Google's own reason (for example "API has not been used in project ... or it is disabled")."""
import getpass
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

NAIROBI = (-1.2921, 36.8219)
KEY = os.environ.get("MAPS_SERVER_KEY", "").strip()
if not KEY or KEY.lower() == "unset":
    KEY = getpass.getpass("Paste the server key (typing is hidden), then press Enter: ").strip()
if len(KEY) < 20:
    sys.exit("That does not look like an API key. Nothing was sent.")


def scrub(text):
    return str(text).replace(KEY, "<key>")


def call(url, headers=None, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, headers=headers or {}, method="POST" if body is not None else "GET")
    try:
        with urllib.request.urlopen(req, timeout=12) as r:  # noqa: S310 - fixed https URLs
            return r.status, json.loads(r.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read().decode() or "{}")
        except Exception:  # noqa: BLE001
            return e.code, {}
    except Exception as e:  # noqa: BLE001
        return 0, {"error": {"message": f"{type(e).__name__}: {scrub(e)}"}}


def reason(code, data):
    err = data.get("error") or {}
    msg = err.get("message") or data.get("error_message") or data.get("status") or f"HTTP {code}"
    return scrub(msg)[:300]


results = []

q = urllib.parse.urlencode({"latlng": f"{NAIROBI[0]},{NAIROBI[1]}", "key": KEY})
code, d = call("https://maps.googleapis.com/maps/api/geocode/json?" + q)
ok = code == 200 and d.get("status") == "OK" and bool(d.get("results"))
results.append(("Geocoding API (street name)", ok, "" if ok else f"{d.get('status', '')} {reason(code, d)}"))

body = {"includedTypes": ["hospital"], "maxResultCount": 3, "locationRestriction": {"circle": {"center": {"latitude": NAIROBI[0], "longitude": NAIROBI[1]}, "radius": 5000.0}}}
code, d = call("https://places.googleapis.com/v1/places:searchNearby", {"Content-Type": "application/json", "X-Goog-Api-Key": KEY, "X-Goog-FieldMask": "places.id,places.displayName"}, body)
ok = code == 200 and bool(d.get("places"))
results.append(("Places API (New) (nearby facilities)", ok, "" if ok else reason(code, d)))

body = {"origin": {"location": {"latLng": {"latitude": NAIROBI[0], "longitude": NAIROBI[1]}}}, "destination": {"location": {"latLng": {"latitude": -1.30, "longitude": 36.80}}}, "travelMode": "DRIVE"}
code, d = call("https://routes.googleapis.com/directions/v2:computeRoutes", {"Content-Type": "application/json", "X-Goog-Api-Key": KEY, "X-Goog-FieldMask": "routes.duration,routes.distanceMeters"}, body)
ok = code == 200 and bool(d.get("routes"))
results.append(("Routes API (road minutes)", ok, "" if ok else reason(code, d)))

print()
for name, ok, why in results:
    print(("PASS  " if ok else "FAIL  ") + name + ("" if ok else "\n      why: " + why))
print()
if all(ok for _, ok, _ in results):
    print("ALL PASS. Now set the secret and redeploy:  firebase functions:secrets:set MAPS_SERVER_KEY   then   firebase deploy --only functions")
else:
    print("Some checks failed. Fix the 'why' lines in Google Cloud Console (enable the API, wait up to 5 minutes, check the key's API restrictions) and run this again.")
