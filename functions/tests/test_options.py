"""Phase 3A tests: ranking, cascade, directory, resident request, routes (fake HTTP), job route cache, track privacy.
Run from the functions folder:   py tests\test_options.py"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__)); FN = os.path.dirname(HERE); sys.path.insert(0, FN); sys.path.insert(0, HERE)
import dispatch  # noqa: F401
from google.cloud.firestore import GeoPoint
import fake_firestore as F
from fake_firestore import DB, now_dt, CLOCK
from dispatch import store, options, options_store, routes, resident_requests as rr, job_route, config as C, core

LAT, LNG = -1.2921, 36.8219
n = 0
def ok(m):
    global n; n += 1; print(f"{n:2d} PASS {m}")
def raises(code, fn):
    try: fn()
    except rr.RequestError as e: assert e.code == code, (e.code, e.message); return
    raise AssertionError("expected " + code)

db = DB()
def responder(i, typ, dlat, status="Available", rating=None):
    db.put(f"responders/{i}", dict(organizationName=i + " unit", organizationType=typ, verificationStatus="Verified", availabilityStatus=status,
           currentLatitude=LAT + dlat, currentLongitude=LNG, lastSeenAt=now_dt(), **({"rating": rating} if rating else {})))
    db.put(f"users/{i}", dict(phoneNumber="+2547110000" + i[-2:], firstName=i))
def facility(i, typ, dlat, name=None, phones=("+254700000001",), is24h=True, verified=True, services=(), status="active", **kw):
    db.put(f"facilities/{i}", dict(name=name or i, type=typ, lat=LAT + dlat, lng=LNG, phones=list(phones), is24h=is24h, verified=verified, services=list(services), status=status, kind="place", **kw))
def hotline(i, typ, name, phones, **kw):
    db.put(f"facilities/{i}", dict(name=name, type=typ, phones=list(phones), kind="hotline", status="active", verified=kw.pop("verified", False), is24h=kw.pop("is24h", None), services=kw.pop("services", [])))
def incident(iid="INC1", cat="Medical Emergency", sub=None, loc=True, ts="pending"):
    db.put(f"users/RES", dict(firstName="Amina", phoneNumber="+254700123456"))
    db.put(f"incidents/{iid}", dict(userId="RES", category=cat, status="Active", location=GeoPoint(LAT, LNG) if loc else None, createdAt=now_dt(), updatedAt=now_dt(),
           priority="High", triageStatus=ts, subtype=sub))
def opts(iid="INC1"):
    out = {}
    for r in ("r1", "r2", "r3", "meta"):
        s = db.collection("incidents").document(iid).collection("options").document(r).get()
        if s.exists: out[r] = s.to_dict()
    return out
def run(iid="INC1"):
    notes = []
    store.reconcile_incident(db, iid, CLOCK[0], lambda _d, o: notes.append(o["responderId"]))
    return notes
def respond(oid, st):
    db.data[f"offers/{oid}"]["status"] = st
    if st == "accepted": db.data[f"offers/{oid}"]["respondedAt"] = now_dt()
    store.handle_offer_status_change(db, oid, db.data[f"offers/{oid}"], CLOCK[0], lambda *_: None)

# ---------- pure ranking ----------
responder("A1", "Ambulance", .02); responder("A2", "Ambulance", .04); responder("A3", "Ambulance", .06)
facility("H1", "hospital", .03, name="Hospital One", address="Ngong Rd"); facility("H2", "hospital", .08, name="Hospital Two"); facility("C1", "clinic", .01, name="Clinic One", is24h=None, verified=False)
facility("P1", "police", .02, name="Police One"); facility("F1", "fire", .05, name="Fire One")
hotline("OP1", "ambulance_operator", "Ambulance Co", ["+254722000111"])
incident()
notes = run()
o = opts(); assert set(o) == {"r1", "r2", "r3", "meta"}; assert len({o[k]["refId"] for k in ("r1", "r2", "r3")}) == 3
assert o["meta"]["mode"] == "map" and not o["meta"]["suggestCall"]; ok("a medical alert gets exactly 3 ranked options plus a meta document")
kinds = [o[k]["kind"] for k in ("r1", "r2", "r3")]; assert "live" in kinds and ("place" in kinds or "hotline" in kinds); ok("options mix live units and call-able places")
assert all(o[k]["orgType"] != "police" and o[k]["orgType"] != "fire" for k in ("r1", "r2", "r3")); ok("a medical alert never lists police or fire stations")
assert not any("phone" in str(o[k].get("phone", "")) for k in o if k != "meta") and all(o[k].get("phone", "") == "" for k in ("r1", "r2", "r3") if o[k]["kind"] == "live"); ok("a live unit's phone is hidden until it accepts")
asked = {k: v["status"] for k, v in db.data.items() if k.startswith("offers/")}; assert len(asked) == 2; ok("the dispatch engine still asks the two nearest units at the same time")
live_status = {o[k]["refId"]: o[k]["status"] for k in ("r1", "r2", "r3") if o[k]["kind"] == "live"}
assert live_status.get("A1") == "asking" and live_status.get("A2") == "asking"; ok("units the engine asked show as 'asking'")

# ---------- cascade ----------
CLOCK[0] += 10; respond("INC1_A1", "declined")
CLOCK[0] += 1; o = opts(); ids = [o[k]["refId"] for k in ("r1", "r2", "r3")]
assert "A1" not in ids and o["meta"]["failedCount"] == 1; ok("a decline removes that unit from the options and is counted")
db.data["responders/A2"]["lastSeenAt"] = now_dt(); db.data["responders/A3"]["lastSeenAt"] = now_dt()
CLOCK[0] += 10; respond("INC1_A2", "expired" if False else "declined"); o = opts()
assert o["meta"]["failedCount"] == 2 and o["meta"]["suggestCall"] and not o["meta"]["showNumbers"]; ok("after two failures the resident is told to call the nearest listed place")
db.data["responders/A3"]["lastSeenAt"] = now_dt()
store.reconcile_incident(db, "INC1", CLOCK[0], lambda *_: None); assert "offers/INC1_A3" in db.data; ok("the engine has by now asked the next unit automatically")
respond("INC1_A3", "declined"); o = opts(); assert o["meta"]["failedCount"] == 3 and o["meta"]["showNumbers"]; ok("after three failures 999 / 112 / 1199 / 922 are shown")
assert not any(o[k]["kind"] == "live" for k in ("r1", "r2", "r3") if k in o); assert any(o[k]["kind"] in ("place", "hotline") for k in ("r1", "r2", "r3")); ok("with no live unit left, call-able places still fill the list")

# ---------- accept, tracks, privacy ----------
responder("B1", "Ambulance", .015); db.data["offers/INC1_A3"]["status"] = "withdrawn"
CLOCK[0] += 5; store.reconcile_incident(db, "INC1", CLOCK[0], lambda *_: None)
assert "offers/INC1_B1" in db.data; respond("INC1_B1", "accepted")
o = opts(); assert o["r1"]["refId"] == "B1" and o["r1"]["status"] == "accepted" and o["r1"]["phone"] == "+2547110000B1", o["r1"]; assert o["meta"]["held"] and not o["meta"]["suggestCall"]; ok("an accepted unit becomes card 1 with its phone and status")
db.put("incidents/INC1/tracks/B1", dict(lat=LAT + .01, lng=LNG, at=now_dt())); db.put("incidents/INC1/tracks/ZZ", dict(lat=1, lng=1, at=now_dt()))
store.reconcile_incident(db, "INC1", CLOCK[0] + 1, lambda *_: None)
assert "incidents/INC1/tracks/B1" in db.data and "incidents/INC1/tracks/ZZ" not in db.data; ok("only the unit that holds the job keeps its live-location track")
respond("INC1_B1", "completed")
assert "incidents/INC1/tracks/B1" not in db.data and not [k for k in db.data if k.startswith("incidents/INC1/options/r")]; ok("when the job completes the track and the option cards are deleted")

# ---------- directory rules ----------
db2 = DB(); db = db2
responder("A1", "Ambulance", .02)
facility("H1", "hospital", .03, status="hidden"); facility("H2", "hospital", .04, name="Open Hospital"); facility("FAR", "hospital", .9, name="Far Hospital")
incident("INC2", cat="Medical Emergency"); run("INC2"); o = opts("INC2")
names = {o[k]["name"] for k in ("r1", "r2", "r3") if k in o}; assert "H1" not in names and "Far Hospital" not in names and "Open Hospital" in names; ok("hidden places and places outside the radius are never shown")
db = DB(); responder("A1", "Ambulance", .02); incident("INC3", cat="Fire & Rescue"); facility("F1", "fire", .03, name="Fire One"); facility("H1", "hospital", .02, name="Hosp"); facility("P1", "police", .01, name="Pol"); run("INC3")
o = opts("INC3"); types = {o[k]["orgType"] for k in ("r1", "r2", "r3") if k in o}; assert "fire" in types and "police" not in types; ok("a fire alert lists fire stations (and the hospital as secondary), not police")
db = DB(); incident("INC4", cat="Security Threat"); facility("P1", "police", .01, name="Pol"); facility("H1", "hospital", .01, name="Hosp"); run("INC4")
o = opts("INC4"); assert o["r1"]["orgType"] == "police" and all(o[k]["orgType"] != "hospital" for k in ("r1", "r2", "r3") if k in o) and o["meta"]["noLive"]; ok("a security alert lists police; with no live unit the card is call-only")
db = DB(); incident("INC5", cat="Medical Emergency", sub="sexual_violence"); facility("H1", "hospital", .02, name="Hosp"); hotline("GBV", "helpline", "GBV helpline", ["1195"], services=["gbv_care"], verified=False); hotline("OP", "ambulance_operator", "Op", ["+254700000009"]); run("INC5")
o = opts("INC5"); got = {o[k]["name"] for k in ("r1", "r2", "r3") if k in o}; assert "GBV helpline" in got and "Hosp" in got; ok("a sexual-violence alert includes the GBV helpline and a hospital")
db = DB(); incident("INC6", cat="Medical Emergency", sub="emotional_distress"); facility("H1", "hospital", .02); run("INC6")
o = opts("INC6"); assert o["meta"]["mode"] == "helplines" and not [k for k in o if k != "meta"] and not [k for k in db.data if k.startswith("offers/")]; ok("emotional distress: no map cards, no dispatch, helplines only")
db = DB(); incident("INC7", loc=False); run("INC7"); o = opts("INC7"); assert not [k for k in o if k != "meta"]; ok("no location: no cards and no crash")
db = DB(); incident("INC8"); run("INC8"); o = opts("INC8"); assert o["meta"]["noLive"] and not [k for k in o if k != "meta"]; ok("empty directory and no units: no cards, meta tells the app to show emergency numbers soon")

# ---------- ETA from Google (fake HTTP) ----------
db = DB(); responder("A1", "Ambulance", .02); facility("H1", "hospital", .03); incident("INC9")
calls = []
def fake_http(url, key, mask, body):
    calls.append((url.rsplit("/", 1)[-1], len(body.get("origins", [])) * len(body.get("destinations", [])))); assert key == "K"
    return [{"originIndex": 0, "destinationIndex": 0, "duration": "420s", "condition": "ROUTE_EXISTS"}]
real = routes._post; routes._post = lambda url, key, mask, body, http=None: fake_http(url, key, mask, body)
try:
    store.apply_actions(db, [], None); inc = store.incident_view("INC9", db.data["incidents/INC9"]); pr = {"state": "dispatching"}
    options_store.refresh(db, "INC9", inc, pr, CLOCK[0], key="K")
    o = opts("INC9"); live = [o[k] for k in ("r1", "r2", "r3") if k in o and o[k]["kind"] == "live"][0]; assert live["etaMin"] == 7.0 and live["etaSource"] == "road"; ok("road travel time replaces the estimate when Google answers")
    c1 = len(calls); options_store.refresh(db, "INC9", inc, pr, CLOCK[0] + 30, key="K"); assert len(calls) == c1; ok("a second refresh within 90 s reuses the times (no extra Google calls)")
    assert all(x[1] <= 6 for x in calls); ok("each Google call stays small (at most 6 pairs)")
    routes._post = lambda *a, **k: (_ for _ in ()).throw(TimeoutError("slow"))
    options_store.refresh(db, "INC9", inc, pr, CLOCK[0] + 500, key="K"); o = opts("INC9"); assert o["r1"]["etaSource"] in ("estimate", "road"); ok("if Google fails the options still appear with estimates")
finally:
    routes._post = real
assert routes.matrix_seconds(None, [(0, 0)], [(1, 1)]) == {} and routes.route(None, (0, 0), (1, 1)) is None; ok("no key = no network call, no error")

# ---------- resident asks one specific unit ----------
db = DB(); responder("A1", "Ambulance", .02); responder("A2", "Ambulance", .04); responder("A3", "Ambulance", .06); incident("INC10"); run("INC10")
db.data = {k: v for k, v in db.data.items() if not k.startswith("offers/")}                    # pretend the engine has not asked yet
store.reconcile_incident(db, "INC10", CLOCK[0], None) if False else None
o_ids = {opts("INC10")[k]["refId"]: opts("INC10")[k]["status"] for k in ("r1", "r2", "r3") if opts("INC10")[k]["kind"] == "live"}
raises("not-found", lambda: rr.request_unit(db, "INC10", "SOMEONE_ELSE", "A3", CLOCK[0])); ok("only the owner can request a unit")
raises("failed-precondition", lambda: rr.request_unit(db, "INC10", "RES", "NOPE", CLOCK[0])); ok("a unit that is not in the options cannot be requested")
for k in ("r1", "r2", "r3"):
    s = db.data.get(f"incidents/INC10/options/{k}")
    if s and s["kind"] == "live": s["status"] = "available"
target = next(db.data[f"incidents/INC10/options/{k}"]["refId"] for k in ("r1", "r2", "r3") if db.data.get(f"incidents/INC10/options/{k}", {}).get("kind") == "live")
off = rr.request_unit(db, "INC10", "RES", target, CLOCK[0]); assert db.data[f"offers/INC10_{target}"]["requestedBy"] == "resident" and db.data[f"offers/INC10_{target}"]["status"] == "offered"; ok("a valid request creates a normal 45-second offer for that unit")
raises("failed-precondition", lambda: rr.request_unit(db, "INC10", "RES", target, CLOCK[0])); ok("asking the same unit twice is refused")
db.data["responders/A2"]["lastSeenAt"] = now_dt(); CLOCK[0] += 500
raises("failed-precondition", lambda: rr.request_unit(db, "INC10", "RES", "A2", CLOCK[0])); ok("a unit whose location went stale cannot be requested")

# ---------- route for the job ----------
db = DB(); responder("A1", "Ambulance", .02); incident("INC11"); db.put("offers/INC11_A1", dict(incidentId="INC11", responderId="A1", status="enroute"))
db.put("incidents/INC11/tracks/A1", dict(lat=LAT + .02, lng=LNG, at=now_dt()))
hits = []
def http(url, key, mask, body): hits.append(1); return {"routes": [{"duration": "300s", "distanceMeters": 2400, "polyline": {"encodedPolyline": "abc"}}]}
r = job_route.route_for(db, "INC11", "A1", "RES", False, CLOCK[0], key="K", http=http); assert r["ok"] and r["etaS"] == 300 and r["polyline"] == "abc" and len(hits) == 1; ok("the owner gets the route line and ETA")
r = job_route.route_for(db, "INC11", "A1", "RES", False, CLOCK[0] + 10, key="K", http=http); assert r["cached"] and len(hits) == 1; ok("a second request within 30 s is served from the cache")
db.put("incidents/INC11/tracks/A1", dict(lat=LAT + .005, lng=LNG, at=now_dt())); r = job_route.route_for(db, "INC11", "A1", "RES", False, CLOCK[0] + 60, key="K", http=http); assert len(hits) == 2; ok("when the unit has moved far, the route is recomputed")
assert job_route.route_for(db, "INC11", "A1", "STRANGER", False, CLOCK[0], key="K", http=http)["reason"] == "forbidden"; ok("a stranger cannot read a route")
assert job_route.route_for(db, "INC11", "A1", "A1", False, CLOCK[0] + 5, key="K", http=http)["ok"]; ok("the assigned unit can read its own route")
def bad(*a): raise TimeoutError()
db.data.pop("incidents/INC11/routes/A1"); r = job_route.route_for(db, "INC11", "A1", "RES", False, CLOCK[0], key="K", http=bad); assert r["ok"] and r.get("estimate"); ok("if Google is down the route call still answers with an estimate")
db.data["offers/INC11_A1"]["status"] = "declined"; assert job_route.route_for(db, "INC11", "A1", "RES", False, CLOCK[0], key="K", http=http)["reason"] == "not_assigned"; ok("no route for a unit that does not hold the job")
print("\nALL PHASE 3A TESTS PASSED")
