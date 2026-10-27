r"""Builds the Nairobi directory of LISTED places (hospitals, clinics, police, fire stations, ambulance operators, helplines) in Firestore.
Run from C:\EmergencyResponseSystem\functions with the venv active, after `gcloud auth application-default login`:

  py ..\tools\import_facilities.py --project emergencyresponsesystem-166601 --dry-run     # shows what it WOULD write; changes nothing
  py ..\tools\import_facilities.py --project emergencyresponsesystem-166601               # writes OpenStreetMap places + the call-only services below
  py ..\tools\import_facilities.py --project emergencyresponsesystem-166601 --csv my_places.csv   # your own list (see CSV_HEADERS)
  py ..\tools\import_facilities.py --project emergencyresponsesystem-166601 --osm-file overpass.json   # use a file you downloaded yourself

Sources and licence: OpenStreetMap data is © OpenStreetMap contributors (ODbL). The app shows that credit on the map screen.
Everything imported is UNVERIFIED until an administrator confirms the phone number. Re-running is safe: stable ids, and any place an
administrator has verified or hidden is never overwritten. Nothing is deleted."""
import argparse, csv, json, math, sys, time, urllib.error, urllib.parse, urllib.request

BBOX = (-1.45, 36.65, -1.15, 37.10)       # south, west, north, east: Nairobi County and nearby
OVERPASS = "https://overpass-api.de/api/interpreter"
MIRRORS = [OVERPASS, "https://overpass.kumi.systems/api/interpreter", "https://overpass.private.coffee/api/interpreter"]
# Obvious OpenStreetMap tagging mistakes (a beauty clinic tagged as a hospital, a shop tagged as a police station). Heuristic: an administrator still verifies.
BAD_WORDS = {
    "hospital": ("aesthetic", "skin", "beauty", "salon", "spa ", "barber", "cosmetic", "pharmacy", "chemist", "veterinar", "vet "),
    "clinic": ("aesthetic", "beauty", "salon", "spa ", "barber", "cosmetic", "pharmacy", "chemist", "veterinar", "vet "),
    "police": ("entertainment", "enterprise", "limited", " ltd", "supplies", "hardware", " bar", "hotel", "restaurant", "salon", "shop", "stores", "academy", "school", "church", "sacco"),
    "fire": ("entertainment", "enterprise", "limited", " ltd", "hotel", "restaurant", "salon", "shop"),
}
TYPE_OF = {("amenity", "hospital"): "hospital", ("amenity", "clinic"): "clinic", ("healthcare", "hospital"): "hospital", ("healthcare", "clinic"): "clinic",
           ("amenity", "doctors"): "clinic", ("amenity", "police"): "police", ("amenity", "fire_station"): "fire", ("emergency", "ambulance_station"): "ambulance_operator"}
CSV_HEADERS = "id,name,type,lat,lng,phones,is24h,address,services,county   (type: hospital|clinic|police|fire|ambulance_operator|helpline|other; phones/services separated by ;)"

# Call-only services. Numbers come from public listings (HapaKenya, March 2026; Red Cross 1199) and MUST be verified by an administrator before the demo.
CALL_ONLY = [
    ("hotline_redcross_1199", "Kenya Red Cross emergency line", "helpline", ["1199"], True, []),
    ("hotline_gbv_1195", "National GBV helpline", "helpline", ["1195"], True, ["gbv_care"]),
    ("hotline_stjohn", "St John Ambulance", "ambulance_operator", ["0202210000", "0721225285"], None, []),
    ("hotline_eplus", "E-Plus Emergency Medical Services", "ambulance_operator", ["0700395395", "0738395395"], None, []),
    ("hotline_rescueco", "Rescue.co", "ambulance_operator", ["+254110929011"], None, []),
    ("hotline_nairobi_amb", "Nairobi Ambulance Services", "ambulance_operator", ["0722846963", "0733999911"], None, []),
    ("hotline_nairobi_fire", "Nairobi County Fire & Emergency", "fire", ["0202222181", "0202223182"], None, []),
]


def overpass_query():
    s, w, n, e = BBOX
    parts = []
    for k, v in (("amenity", "hospital"), ("amenity", "clinic"), ("amenity", "police"), ("amenity", "fire_station"), ("emergency", "ambulance_station")):
        parts.append(f'nwr["{k}"="{v}"]({s},{w},{n},{e});')
    return "[out:json][timeout:60];(" + "".join(parts) + ");out center tags;"


def fetch_osm():
    """Overpass is a free shared service and sometimes answers 429/504. Retries with waits and tries mirrors. Raises a readable error."""
    data = urllib.parse.urlencode({"data": overpass_query()}).encode()
    last = "no answer"
    for attempt in range(3):
        for ep in MIRRORS:
            try:
                req = urllib.request.Request(ep, data=data, headers={"User-Agent": "EmergencyResponseSystem-capstone/1.0 (student project)", "Accept": "application/json"})
                with urllib.request.urlopen(req, timeout=100) as r:  # noqa: S310
                    return json.loads(r.read().decode())
            except urllib.error.HTTPError as e:
                last = f"HTTP {e.code} from {ep.split('/')[2]}"
            except Exception as e:  # noqa: BLE001
                last = f"{type(e).__name__} from {ep.split('/')[2]}"
            print(f"  OpenStreetMap server said: {last}. Trying again...")
        time.sleep(15 * (attempt + 1))
    raise RuntimeError(last)


def _phones(tags):
    raw = tags.get("phone") or tags.get("contact:phone") or tags.get("emergency:phone") or ""
    return [p.strip() for p in raw.replace(",", ";").split(";") if p.strip()][:3]


def parse_osm(doc):
    out = []
    for el in doc.get("elements", []):
        tags = el.get("tags") or {}
        typ = next((v for (k, val), v in TYPE_OF.items() if tags.get(k) == val), None)
        lat = el.get("lat") if "lat" in el else (el.get("center") or {}).get("lat")
        lng = el.get("lon") if "lon" in el else (el.get("center") or {}).get("lon")
        name = tags.get("name") or tags.get("official_name")
        if not typ or lat is None or lng is None or not name:
            continue
        low = " " + name.lower() + " "
        if any(w in low for w in BAD_WORDS.get(typ, ())):
            continue
        addr = ", ".join(x for x in (tags.get("addr:street"), tags.get("addr:suburb"), tags.get("addr:city")) if x)
        oh = (tags.get("opening_hours") or "").strip()
        out.append({"id": f"osm_{el.get('type', 'n')[0]}{el['id']}", "name": name.strip(), "type": typ, "lat": float(lat), "lng": float(lng), "phones": _phones(tags),
                    "is24h": True if oh == "24/7" else None, "hours": oh, "address": addr,
                    "services": [], "county": "Nairobi", "source": "osm", "sourceId": f"{el.get('type')}/{el['id']}", "kind": "place"})
    return out


def parse_csv(path):
    out = []
    with open(path, newline="", encoding="utf-8-sig") as f:
        for i, row in enumerate(csv.DictReader(f), 2):
            try:
                typ = row["type"].strip()
                lat, lng = (float(row["lat"]), float(row["lng"])) if row.get("lat") and row.get("lng") else (None, None)
                phones = [p.strip() for p in (row.get("phones") or "").split(";") if p.strip()]
                if lat is not None and not (-5 < lat < 5 and 33 < lng < 42):
                    print(f"  skip row {i}: coordinates are outside Kenya"); continue
                out.append({"id": (row.get("id") or "csv_" + "".join(c for c in row["name"].lower() if c.isalnum())[:40]).strip(), "name": row["name"].strip(), "type": typ,
                            "lat": lat, "lng": lng, "phones": phones, "is24h": {"yes": True, "true": True, "no": False, "false": False}.get((row.get("is24h") or "").lower()),
                            "hours": "", "address": row.get("address", "").strip(), "services": [s.strip() for s in (row.get("services") or "").split(";") if s.strip()],
                            "county": row.get("county", "Nairobi").strip(), "source": "manual", "sourceId": "", "kind": "place" if lat is not None else "hotline"})
            except (KeyError, ValueError) as e:
                print(f"  skip row {i}: {type(e).__name__} {e}")
    return out


def call_only():
    return [{"id": i, "name": n, "type": t, "lat": None, "lng": None, "phones": p, "is24h": h, "hours": "", "address": "", "services": s, "county": "Nairobi",
             "source": "listing", "sourceId": "", "kind": "hotline"} for i, n, t, p, h, s in CALL_ONLY]


def km(a, b):
    dlat, dlng = math.radians(b[0] - a[0]), math.radians(b[1] - a[1])
    x = math.sin(dlat / 2) ** 2 + math.cos(math.radians(a[0])) * math.cos(math.radians(b[0])) * math.sin(dlng / 2) ** 2
    return 6371 * 2 * math.asin(math.sqrt(x))


def dedupe(items):
    """Same name (case-insensitive) within 150 m = one place. Keeps the one with phones."""
    kept = []
    for it in sorted(items, key=lambda x: (not x["phones"], x["id"])):
        if it["lat"] is not None and any(k["lat"] is not None and k["name"].lower() == it["name"].lower() and km((k["lat"], k["lng"]), (it["lat"], it["lng"])) < 0.15 for k in kept):
            continue
        kept.append(it)
    return kept


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--project", required=True)
    ap.add_argument("--csv"); ap.add_argument("--osm-file"); ap.add_argument("--no-osm", action="store_true"); ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    items = []
    if a.csv:
        items += parse_csv(a.csv)
    if not a.no_osm and not a.csv:
        try:
            doc = json.load(open(a.osm_file, encoding="utf-8")) if a.osm_file else fetch_osm()
        except Exception as e:  # noqa: BLE001
            sys.exit(f"Could not get OpenStreetMap data ({e}). Wait a few minutes and run it again, or download the file from https://overpass-turbo.eu yourself and use --osm-file, or use --csv.")
        items += parse_osm(doc)
    if not a.csv:
        items += call_only()
    items = dedupe(items)
    by = {}
    for i in items:
        by[i["type"]] = by.get(i["type"], 0) + 1
    print(f"{len(items)} places ready: {by}")
    if a.dry_run:
        for i in items[:15]:
            print("  ", i["type"].ljust(18), i["name"][:45].ljust(46), i["phones"][:1])
        print("Dry run: nothing written."); return
    import firebase_admin
    from firebase_admin import firestore
    firebase_admin.initialize_app(options={"projectId": a.project})
    db = firestore.client()
    new = upd = skip = 0
    for it in items:
        ref = db.collection("facilities").document(it["id"])
        cur = ref.get()
        doc = {k: v for k, v in it.items() if k != "id"}
        if cur.exists:
            c = cur.to_dict() or {}
            if c.get("verified") or c.get("status") == "hidden" or c.get("verifiedBy"):
                skip += 1; continue
            ref.set({**doc, "status": c.get("status", "active"), "verified": False, "updatedAt": firestore.SERVER_TIMESTAMP}); upd += 1
        else:
            ref.set({**doc, "status": "active", "verified": False, "linkedResponderId": None, "updatedAt": firestore.SERVER_TIMESTAMP}); new += 1
    print(f"Done. new={new} refreshed={upd} left-alone(verified/hidden)={skip}")


if __name__ == "__main__":
    main()
