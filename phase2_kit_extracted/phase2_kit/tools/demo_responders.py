r"""TEST TOOL. Creates pretend verified responders around a point and, while running, answers offers like a real responder would,
so you can watch a whole alert (offer -> accept -> on the way -> arrived -> completed) with ONE phone.
Never used by the real system. Demo records are marked isDemo=true and removed with 'clear'.
Run from C:\EmergencyResponseSystem\functions (after:  gcloud auth application-default login):
    py ..\tools\demo_responders.py --project emergencyresponsesystem-166601 seed  --lat -1.2921 --lng 36.8219
    py ..\tools\demo_responders.py --project emergencyresponsesystem-166601 run             (leave it running; Ctrl+C to stop)
    py ..\tools\demo_responders.py --project emergencyresponsesystem-166601 clear
Use --lat/--lng of the place where you test the phone (units are put 1-4 km around it)."""
import argparse, datetime as dt, random, time
import firebase_admin
from firebase_admin import firestore

ap = argparse.ArgumentParser()
ap.add_argument("--project", required=True)
ap.add_argument("cmd", choices=["seed", "run", "clear"])
ap.add_argument("--lat", type=float, default=-1.2921); ap.add_argument("--lng", type=float, default=36.8219)
ap.add_argument("--decline-rate", type=float, default=0.0, help="share of offers the pretend responders decline (0 to 1)")
a = ap.parse_args()
firebase_admin.initialize_app(options={"projectId": a.project})
db = firestore.client()
UNITS = [("demo_amb_1", "Demo Ambulance 1", "Ambulance", 0.010, 0.004, "+254700000101"), ("demo_amb_2", "Demo Ambulance 2", "Ambulance", -0.018, 0.010, "+254700000102"),
         ("demo_amb_3", "Demo Ambulance 3", "Ambulance", 0.028, -0.012, "+254700000103"), ("demo_fire_1", "Demo Fire Unit", "Fire", -0.012, -0.015, "+254700000104"),
         ("demo_pol_1", "Demo Police Post", "Police", 0.015, 0.012, "+254700000105"), ("demo_pol_2", "Demo Police Post 2", "Police", -0.025, 0.006, "+254700000106"),
         ("demo_hosp_1", "Demo Hospital", "Hospital", 0.020, -0.006, "+254700000107")]
now = lambda: dt.datetime.now(dt.timezone.utc)
if a.cmd == "seed":
    for i, name, typ, dl, dg, phone in UNITS:
        db.collection("responders").document(i).set({"responderId": i, "organizationName": name, "organizationType": typ, "registrationNumber": "DEMO-" + i.upper(),
            "verificationStatus": "Verified", "verificationNotes": "demo", "verifiedBy": "demo", "verifiedAt": now(), "availabilityStatus": "Available",
            "currentLatitude": a.lat + dl, "currentLongitude": a.lng + dg, "serviceArea": "Demo", "createdAt": now(), "updatedAt": now(), "lastSeenAt": now(), "isDemo": True})
        db.collection("users").document(i).set({"userId": i, "firstName": name, "lastName": "", "phoneNumber": phone, "role": "Responder", "accountStatus": "Active", "isDemo": True})
    print(f"Created {len(UNITS)} demo responders around {a.lat}, {a.lng}. Now run:  run")
elif a.cmd == "clear":
    for i, *_ in UNITS:
        db.collection("responders").document(i).delete(); db.collection("users").document(i).delete()
    for s in db.collection("offers").stream():
        if str(s.to_dict().get("responderId", "")).startswith("demo_"): s.reference.delete()
    print("Demo responders and their offers removed.")
else:
    demo = {u[0] for u in UNITS}; plan = {}          # offerId -> list of (time, status)
    print("Running. Demo units answer offers (accept after ~8 s, then progress). Ctrl+C to stop.")
    while True:
        t = time.time()
        for i in demo:
            r = db.collection("responders").document(i).get()
            if r.exists and r.to_dict().get("availabilityStatus") != "Offline":
                db.collection("responders").document(i).update({"lastSeenAt": now()})
        for s in db.collection("offers").stream():
            d = s.to_dict(); oid = s.id
            if d.get("responderId") not in demo: continue
            st = d.get("status")
            if st == "offered" and oid not in plan:
                if random.random() < a.decline_rate: plan[oid] = [(t + 6, "declined")]
                else: plan[oid] = [(t + 8, "accepted"), (t + 16, "enroute"), (t + 40, "arrived"), (t + 70, "completed")]
                print(" offer", oid, "-> will", plan[oid][0][1])
            if st in ("withdrawn", "expired", "declined", "completed"): plan.pop(oid, None)
            while plan.get(oid) and plan[oid][0][0] <= t and st not in ("withdrawn", "expired"):
                _, nxt = plan[oid].pop(0)
                s.reference.update({"status": nxt, "respondedAt": now(), "updatedAt": now()}); st = nxt; print("  ", oid, "->", nxt)
        time.sleep(2)
