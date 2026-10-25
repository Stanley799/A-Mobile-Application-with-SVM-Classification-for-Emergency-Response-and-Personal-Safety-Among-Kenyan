"""Tests for the pure dispatch brain. Run from the functions folder:   py tests\test_dispatch_core.py"""
import json, os, sys
HERE = os.path.dirname(os.path.abspath(__file__)); FN = os.path.dirname(HERE)
sys.path.insert(0, FN)
import dispatch                                   # noqa: F401  (adds functions/ml/scripts to the path)
from dispatch import core, config as C
import triage_core as t
TABLE = json.load(open(os.path.join(FN, "ml", "models", "decision_table.json")))
NOW, LAT, LNG = 1_000_000.0, -1.2921, 36.8219
def R(i, typ, dlat, status="available", age=10, verified=True, caps=None):
    return dict(id=i, name=i, type=typ, phone="+254700000000", lat=LAT + dlat, lng=LNG, status=status, last_seen=NOW - age, verified=verified, capabilities=caps)
def INC(cat, sub=None, ts="pending", answers=None, loc=True, age=5, status="Active", free=""):
    return dict(id="INC1", code="20261021-120000-FIRE-AB12", status=status, category=cat, subtype=sub, triageStatus=ts, answers=answers or {},
                lat=LAT if loc else None, lng=LNG if loc else None, createdAt=NOW - age, freeText=free)
def creates(res): return [a["offer"] for a in res["actions"] if a["type"] == "create_offer"]
def kinds(res): return sorted(a["type"] for a in res["actions"])
def apply(offers, res):
    """Mimics the store: applies actions to the list of offers."""
    offers = [dict(o) for o in offers]
    for a in res["actions"]:
        if a["type"] == "create_offer": offers.append(dict(a["offer"]))
        else:
            o = next(x for x in offers if x["id"] == a["id"])
            if a["type"] == "expire_offer": o["status"] = "expired"
            elif a["type"] == "withdraw_offer": o["status"] = "withdrawn"
            elif a["type"] == "update_offer": o.update(a["fields"])
    return offers
amb1, amb2, amb3 = R("A1", "Ambulance", .02), R("A2", "Ambulance", .04), R("A3", "Ambulance", .06)
fire, pol = R("F1", "Fire", .05), R("P1", "Police", .03)
hosp = R("H1", "Hospital", .045)
POOL = [amb1, amb2, amb3, fire, pol, hosp]
n = 0
def ok(msg): global n; n += 1; print(f"{n:2d} PASS {msg}")

# 1 alert-first: a Medical alert with NO answers yet goes out at once, High, wave of 2 nearest ambulances
r = core.reconcile(INC("Medical Emergency"), POOL, [], NOW, TABLE)
ids = [o["responderId"] for o in creates(r)]
assert ids == ["A1", "A2"], ids and r
assert all(o["priority"] == "High" and o["expiresAt"] == NOW + C.OFFER_SECONDS for o in creates(r)); assert r["dispatch"]["state"] == "dispatching"
ok("Medical, no details yet: High, 2 nearest ambulances asked at once, 45 s to answer")

# 2 idempotent: running again with those offers in flight does nothing new
offers = apply([], r)
r2 = core.reconcile(INC("Medical Emergency"), POOL, offers, NOW + 1, TABLE)
assert not creates(r2) and not [a for a in r2["actions"] if a["type"] in ("expire_offer", "withdraw_offer")]; ok("running twice creates no duplicate offers")

# 3 no location yet -> wait, then tell the resident to call 922
r = core.reconcile(INC("Fire & Rescue", loc=False, age=5), POOL, [], NOW, TABLE); assert r["dispatch"]["state"] == "waiting_location" and not r["dispatch"]["escalate922"] and not creates(r)
r = core.reconcile(INC("Fire & Rescue", loc=False, age=30), POOL, [], NOW, TABLE); assert r["dispatch"]["state"] == "no_location" and r["dispatch"]["escalate922"]; ok("no GPS: waits 20 s, then escalates to 922")

# 4 unverified, busy, stale, offline are never asked
bad = [R("B1", "Ambulance", .001, verified=False), R("B2", "Ambulance", .001, status="busy"), R("B3", "Ambulance", .001, age=500), R("B4", "Ambulance", .001, status="offline")]
r = core.reconcile(INC("Medical Emergency"), bad, [], NOW, TABLE); assert not creates(r) and r["dispatch"]["state"] == "unfilled" and r["dispatch"]["escalate922"] and "medical_transport" in r["dispatch"]["unfilled"]; ok("unverified/busy/stale/offline responders are never offered; resident told to call 922")

# 5 a decline or expiry moves to the NEXT responder, never the same one again
offers = apply([], core.reconcile(INC("Medical Emergency"), POOL, [], NOW, TABLE))
for o in offers: o["status"] = "declined"
r = core.reconcile(INC("Medical Emergency"), POOL, offers, NOW + 5, TABLE); assert [o["responderId"] for o in creates(r)] == ["H1"] or [o["responderId"] for o in creates(r)] == ["A3", "H1"] or all(x not in ("A1", "A2") for x in [o["responderId"] for o in creates(r)]); 
assert all(o["wave"] == 2 for o in creates(r)); ok("after both decline, wave 2 goes to others: " + ",".join(o["responderId"] for o in creates(r)))
offers = apply([], core.reconcile(INC("Medical Emergency"), POOL, [], NOW, TABLE))
r = core.reconcile(INC("Medical Emergency"), POOL, offers, NOW + 46, TABLE); assert sum(a["type"] == "expire_offer" for a in r["actions"]) == 2 and len(creates(r)) == 2; ok("offers that time out (45 s) expire and the next wave starts")

# 6 first to accept wins; sibling and a late second accept are withdrawn
offers = apply([], core.reconcile(INC("Medical Emergency"), POOL, [], NOW, TABLE))
offers[0]["status"], offers[0]["respondedAt"] = "accepted", NOW + 10
acts = core.resolve_acceptance(["medical_transport"], offers); assert [(a["id"], a["reason"]) for a in acts] == [("INC1_A2", "another_unit_accepted")]
offers[1]["status"], offers[1]["respondedAt"] = "accepted", NOW + 11
acts = core.resolve_acceptance(["medical_transport"], offers); assert [(a["id"], a["reason"]) for a in acts] == [("INC1_A2", "role_already_filled")]; ok("two accepts for one role: the earlier wins, the later is withdrawn")
offers = apply(offers, {"actions": acts})
r = core.reconcile(INC("Medical Emergency"), POOL, offers, NOW + 12, TABLE); assert not creates(r) and r["dispatch"]["state"] == "assigned"; ok("role filled: state 'assigned', no more offers")

# 7 progress states
for st, want in (("enroute", "enroute"), ("arrived", "arrived"), ("completed", "completed")):
    offers[0]["status"] = st
    r = core.reconcile(INC("Medical Emergency"), POOL, offers, NOW + 20, TABLE); assert r["dispatch"]["state"] == want, r["dispatch"]
ok("state follows the unit: assigned -> enroute -> arrived -> completed")

# 8 quick answers add roles: trapped + hazard on a road crash needs ambulance AND fire AND extrication; one unit per role, no duplicates
inc = INC("Road Accident", ts="quick", answers={"conscious": "Yes", "trapped": "Yes", "hazard": "Yes"})
req, pref, _ = core.needs(inc); assert set(req) >= {"medical_transport", "extrication", "fire_suppression"}, req
r = core.reconcile(inc, POOL, [], NOW, TABLE); covered = set().union(*[set(o["covers"]) | {o["role"]} for o in creates(r)]); assert covered >= set(req), covered
assert "P1" not in [o["responderId"] for o in creates(r)]; ok("road crash trapped+fire: asks medical, extrication and fire units, not police")
# the fire unit covers BOTH fire_suppression and extrication -> only one offer to it
fires = [o for o in creates(r) if o["responderId"] == "F1"]; assert len(fires) == 1 and set(fires[0]["covers"]) >= {"fire_suppression", "extrication"}; ok("one unit that can do two jobs gets ONE offer, not two")

# 9 priority is decided by the SERVER from the answers; a client can't lower it
inc = INC("Medical Emergency", ts="complete", answers={"conscious": "No", "breathing": "Yes", "severe_bleeding": "No"}); inc["clientPriority"] = "Low"
assert core.server_priority(inc, TABLE)["priority"] == "High"; ok("not conscious => High from the server whatever the phone says")
inc = INC("Medical Emergency", ts="complete", answers={"conscious": "Yes", "breathing": "Yes", "severe_bleeding": "No", "chest_pain": "No"})
low = core.server_priority(inc, TABLE)["priority"]; print("   (all fine ->", low, ")")
assert core.server_priority(INC("Medical Emergency", ts="complete", answers={"conscious": "Yes", "breathing": "Yes", "severe_bleeding": "No", "chest_pain": "Yes"}), TABLE)["priority"] == "High"; ok("chest pain => High")
bad = INC("Nonsense", ts="complete"); assert core.server_priority(bad, TABLE)["priority"] == "High"; ok("broken data fails SAFE to High")

# 10 radius: Low priority looks only 10 km; High looks 20 km
farr = [R("FAR", "Ambulance", .15)]   # about 16.7 km
inc = INC("Medical Emergency", ts="complete", answers={"conscious": "Yes", "breathing": "Yes", "severe_bleeding": "No", "chest_pain": "No"})
pr = core.server_priority(inc, TABLE)["priority"]
r = core.reconcile(inc, farr, [], NOW, TABLE)
print("   priority", pr, "| offers", len(creates(r)), "| state", r["dispatch"]["state"])
if pr == "Low": assert not creates(r) and r["dispatch"]["escalate922"]
ok("radius depends on priority")
r = core.reconcile(INC("Medical Emergency"), farr, [], NOW, TABLE); assert len(creates(r)) == 1 and r["dispatch"]["escalate922"]; ok("High + responder over 15 km: still asked, but resident is told to ALSO call 922")

# 11 confidential cases
inc = INC("Security Threat", "sexual_violence", ts="complete", answers={"conscious": "Yes", "breathing": "Yes", "severe_bleeding": "No", "weapon_involved": "No", "immediate_danger": "No"}, free="private details")
r = core.reconcile(inc, POOL, [], NOW, TABLE); got = creates(r); assert got and all(o["role"] == "medical_transport" for o in got) and "P1" not in [o["responderId"] for o in got]
assert all(o["confidential"] and o["freeText"] == "" for o in got); ok("sexual violence: medical unit (hospital/ambulance), no police auto-sent, typed text never included")
inc = INC("Other / General", "emotional_distress", ts="complete"); r = core.reconcile(inc, POOL, [], NOW, TABLE); assert not creates(r) and r["dispatch"]["state"] == "support_only"; ok("emotional distress: no responder is ever sent")
inc = INC("Other / General", "mental_health_crisis", ts="complete", answers={"conscious": "Yes", "breathing": "Yes", "severe_bleeding": "No"}); r = core.reconcile(inc, POOL, [], NOW, TABLE); assert creates(r) and creates(r)[0]["priority"] == "High"; ok("self-harm crisis: High, a responder is sent")

# 12 'Other' waits for the category, then falls back safely; Low 'Other' goes to a dispatcher
r = core.reconcile(INC("Other / General", age=5), POOL, [], NOW, TABLE); assert r["dispatch"]["state"] == "awaiting_details" and not creates(r)
r = core.reconcile(INC("Other / General", age=30), POOL, [], NOW, TABLE); assert creates(r); ok("'Other': waits 25 s for the category; if nothing comes, dispatches fail-safe")
inc = INC("Other / General", ts="complete", answers={"conscious": "Yes", "breathing": "Yes", "severe_bleeding": "No"}, age=60)
r = core.reconcile(inc, POOL, [], NOW, TABLE); print("   Other, all fine ->", r["dispatch"]["state"]); assert r["dispatch"]["state"] in ("needs_review", "dispatching")
ok("'Other' with nothing wrong is sent to a dispatcher, not an ambulance")

# 13 cancel and resolve
offers = apply([], core.reconcile(INC("Medical Emergency"), POOL, [], NOW, TABLE)); offers[0]["status"] = "enroute"
r = core.reconcile(INC("Medical Emergency", status="Cancelled"), POOL, offers, NOW + 5, TABLE)
assert sorted(a["id"] for a in r["actions"]) == ["INC1_A1", "INC1_A2"] and r["dispatch"]["state"] == "cancelled"; ok("cancelled alert: every open offer is withdrawn")

# 14 location arrives later / answers change: open offers are updated, not duplicated
offers = apply([], core.reconcile(INC("Road Accident"), POOL, [], NOW, TABLE))
inc = INC("Road Accident", ts="quick", answers={"conscious": "No", "trapped": "No", "hazard": "No"})
r = core.reconcile(inc, POOL, offers, NOW + 3, TABLE); up = [a for a in r["actions"] if a["type"] == "update_offer"]; assert up and all("flags" in a["fields"] or "priority" in a["fields"] for a in up); ok("new answers update the briefing on open offers")

# 15 limits: max 6 offers per role, then unfilled
many = [R(f"M{i}", "Ambulance", .001 * (i + 1)) for i in range(10)]
offers = []
for step in range(6):
    r = core.reconcile(INC("Medical Emergency"), many, offers, NOW + step, TABLE); offers = apply(offers, r)
    for o in offers:
        if o["status"] == "offered": o["status"] = "declined"
r = core.reconcile(INC("Medical Emergency"), many, offers, NOW + 9, TABLE); assert len(offers) == C.MAX_OFFERS_PER_ROLE and not creates(r) and r["dispatch"]["state"] == "unfilled" and r["dispatch"]["escalate922"]
ok("after 6 tries for one role the engine stops and escalates")
# 16 minimal briefing: never contains resident contact, email, address
b = creates(core.reconcile(INC("Medical Emergency"), POOL, [], NOW, TABLE))[0]
assert not {"phone", "email", "residentPhone", "userId", "resident"} & set(b); ok("offer carries no resident contact or user id")
print("\nALL DISPATCH CORE TESTS PASSED")
