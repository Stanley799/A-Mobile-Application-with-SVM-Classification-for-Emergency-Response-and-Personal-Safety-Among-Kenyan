"""End-to-end test of store.py against an in-memory Firestore: alert -> offers -> accept -> en route -> arrived -> completed, plus
decline, expiry, cancel, sweep and 'two phones accept at once'. Run from the functions folder:   py tests\test_store_lifecycle.py"""
import datetime as dt, os, sys
HERE = os.path.dirname(os.path.abspath(__file__)); FN = os.path.dirname(HERE); sys.path.insert(0, FN)
import dispatch  # noqa: F401
from google.api_core.exceptions import AlreadyExists
from google.cloud.firestore import GeoPoint, SERVER_TIMESTAMP
from dispatch import store, config as C

CLOCK = [1_000_000.0]
def now_dt(): return dt.datetime.fromtimestamp(CLOCK[0], tz=dt.timezone.utc)
def fix(v):
    if v is SERVER_TIMESTAMP: return now_dt()
    if isinstance(v, dict): return {k: fix(x) for k, x in v.items()}
    return v
class Snap:
    def __init__(s, ref, d): s.reference, s.id, s._d = ref, ref.id, d
    @property
    def exists(s): return s._d is not None
    def to_dict(s): return dict(s._d) if s._d is not None else None
class Ref:
    def __init__(s, db, col, id): s.db, s.col, s.id = db, col, id
    def get(s): return Snap(s, s.db.data.get(s.col, {}).get(s.id))
    def set(s, d): s.db.data.setdefault(s.col, {})[s.id] = fix(dict(d))
    def create(s, d):
        if s.id in s.db.data.get(s.col, {}): raise AlreadyExists("exists")
        s.set(d)
    def update(s, d):
        cur = s.db.data[s.col][s.id]; cur.update(fix(dict(d)))
class Query:
    def __init__(s, db, col, f=()): s.db, s.col, s.f = db, col, f
    def where(s, k, op, v): assert op == "=="; return Query(s.db, s.col, s.f + ((k, v),))
    def stream(s):
        for id, d in list(s.db.data.get(s.col, {}).items()):
            if all(d.get(k) == v for k, v in s.f): yield Snap(Ref(s.db, s.col, id), d)
class Col(Query):
    def document(s, id): return Ref(s.db, s.col, id)
    def add(s, d): s.db.data.setdefault(s.col, {})[f"auto{len(s.db.data.get(s.col, {}))}"] = fix(dict(d))
class DB:
    def __init__(s): s.data = {}
    def collection(s, name): return Col(s, name)

LAT, LNG = -1.2921, 36.8219
db = DB(); pushes = []
def notify(_db, o): pushes.append(o["responderId"])
def add_responder(i, typ, dlat, phone):
    db.data.setdefault("responders", {})[i] = dict(organizationName=i + " unit", organizationType=typ, verificationStatus="Verified", availabilityStatus="Available",
        currentLatitude=LAT + dlat, currentLongitude=LNG, lastSeenAt=now_dt())
    db.data.setdefault("users", {})[i] = dict(phoneNumber=phone, firstName=i)
add_responder("A1", "Ambulance", .02, "+254711000001"); add_responder("A2", "Ambulance", .04, "+254711000002"); add_responder("A3", "Ambulance", .06, "+254711000003")
db.data.setdefault("users", {})["RES"] = dict(firstName="Amina", phoneNumber="+254700123456")
def new_incident(iid="INC1", cat="Medical Emergency", loc=True, sub=None, ts="pending"):
    db.data.setdefault("incidents", {})[iid] = dict(userId="RES", category=cat, status="Active", location=GeoPoint(LAT, LNG) if loc else None, createdAt=now_dt(),
        updatedAt=now_dt(), priority="High", prioritySource="safe_fallback", needsHumanReview=True, triageStatus=ts, subtype=sub)
def offers(iid="INC1"): return {k: v for k, v in db.data.get("offers", {}).items() if v["incidentId"] == iid}
def respond(oid, status):
    db.data["offers"][oid]["status"] = status
    if status in ("accepted",): db.data["offers"][oid]["respondedAt"] = now_dt()
    return store.handle_offer_status_change(db, oid, db.data["offers"][oid], CLOCK[0], notify)
n = 0
def ok(m): global n; n += 1; print(f"{n:2d} PASS {m}")

new_incident(); store.reconcile_incident(db, "INC1", CLOCK[0], notify)
o = offers(); assert set(o) == {"INC1_A1", "INC1_A2"} and sorted(pushes) == ["A1", "A2"] and o["INC1_A1"]["resident"] is None
inc = db.data["incidents"]["INC1"]; assert inc["dispatch"]["state"] == "dispatching" and inc["status"] == "Active"; ok("alert -> 2 offers created, both phones pushed, state 'dispatching'")
assert "userId" not in o["INC1_A1"] and "phone" not in str(o["INC1_A1"]); ok("stored offer has no resident id or phone")
store.reconcile_incident(db, "INC1", CLOCK[0] + 1, notify); assert len(offers()) == 2 and len(pushes) == 2; ok("re-running does not duplicate offers or pushes")

# A2 accepts first, A1 (slower) is withdrawn
CLOCK[0] += 10; db.data["responders"]["A2"]["lastSeenAt"] = now_dt(); respond("INC1_A2", "accepted")
assert db.data["responders"]["A2"]["availabilityStatus"] == "Busy"; ok("accepting marks the responder Busy (server side)")
o = offers(); assert o["INC1_A2"]["status"] == "accepted" and o["INC1_A1"]["status"] == "withdrawn" and o["INC1_A1"]["withdrawReason"] == "another_unit_accepted"
assert o["INC1_A2"]["resident"] == {"firstName": "Amina", "phone": "+254700123456"}; ok("first accept wins, the other is withdrawn, contact released only to the winner")
d = db.data["incidents"]["INC1"]["dispatch"]; assert d["state"] == "assigned" and d["units"][0]["phone"] == "+254711000002" and d["units"][0]["name"] == "A2 unit"; ok("resident sees the unit's name and phone")
for st, want in (("enroute", "enroute"), ("arrived", "arrived")):
    CLOCK[0] += 30; respond("INC1_A2", st); assert db.data["incidents"]["INC1"]["dispatch"]["state"] == want
ok("progress shown to the resident")
CLOCK[0] += 600; respond("INC1_A2", "completed"); inc = db.data["incidents"]["INC1"]
assert inc["dispatch"]["state"] == "completed" and inc["status"] == "Resolved" and "resolvedAt" in inc and inc["dispatch"]["units"]; ok("all units completed -> incident Resolved, units still listed")
store.reconcile_incident(db, "INC1", CLOCK[0] + 1, notify); assert db.data["incidents"]["INC1"]["status"] == "Resolved" and len(offers()) == 2; ok("a resolved incident stays quiet")

assert db.data["responders"]["A2"]["availabilityStatus"] == "Available"; ok("after completing, the responder is Available again")
# decline -> next
CLOCK[0] += 100; [db.data["responders"][k].update(lastSeenAt=now_dt()) for k in db.data["responders"]]; new_incident("INC2"); pushes.clear(); store.reconcile_incident(db, "INC2", CLOCK[0], notify)
o = offers("INC2"); assert set(o) == {"INC2_A1", "INC2_A2"}
respond("INC2_A1", "declined"); assert "INC2_A3" not in offers("INC2"); respond("INC2_A2", "declined")
o = offers("INC2"); assert "INC2_A3" in o and o["INC2_A3"]["wave"] == 2 and "A3" in pushes; ok("both decline -> the next responder (A3) is asked and pushed")

# expiry via sweep
CLOCK[0] += 50; pushes.clear()
for k in list(db.data["responders"]): db.data["responders"][k]["lastSeenAt"] = now_dt()
ran = store.sweep(db, CLOCK[0], notify); o = offers("INC2")
assert o["INC2_A3"]["status"] == "expired" and "INC2" in ran; d = db.data["incidents"]["INC2"]["dispatch"]; assert d["state"] == "unfilled" and d["escalate922"]; ok("unanswered offer expires in the sweep; nobody left -> state 'unfilled', resident told to call 922")

# cancel
new_incident("INC3"); store.reconcile_incident(db, "INC3", CLOCK[0], notify); respond("INC3_A1", "accepted")
assert db.data["responders"]["A1"]["availabilityStatus"] == "Busy"
db.data["incidents"]["INC3"]["status"] = "Cancelled"; store.reconcile_incident(db, "INC3", CLOCK[0] + 5, notify)
assert db.data["responders"]["A1"]["availabilityStatus"] == "Available"
assert all(v["status"] == "withdrawn" for v in offers("INC3").values()) and db.data["incidents"]["INC3"]["dispatch"]["state"] == "cancelled"; ok("resident cancels -> every open offer withdrawn")

# location arrives late
for k in list(db.data["responders"]): db.data["responders"][k]["lastSeenAt"] = now_dt(); db.data["responders"][k]["availabilityStatus"] = "Available"
new_incident("INC4", loc=False); store.reconcile_incident(db, "INC4", CLOCK[0], notify)
assert db.data["incidents"]["INC4"]["dispatch"]["state"] == "waiting_location" and not offers("INC4")
db.data["incidents"]["INC4"]["location"] = GeoPoint(LAT, LNG); store.reconcile_incident(db, "INC4", CLOCK[0] + 2, notify); assert len(offers("INC4")) == 2; ok("GPS arrives after the alert -> dispatch starts")

# stale responder set offline by sweep
CLOCK[0] += 700; ran = store.sweep(db, CLOCK[0], notify); assert all(r["availabilityStatus"] == "Offline" for r in db.data["responders"].values()); ok("silent responders are set Offline")
print("\nALL STORE LIFECYCLE TESTS PASSED")
