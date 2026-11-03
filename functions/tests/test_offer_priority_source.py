"""Offers carry where their priority came from, so a responder can tell a real High from the default High.
Run from the functions folder:   py tests\test_offer_priority_source.py"""
import json, os, sys
HERE = os.path.dirname(os.path.abspath(__file__)); FN = os.path.dirname(HERE)
sys.path.insert(0, FN)
import dispatch                                   # noqa: F401
from dispatch import core
TABLE = json.load(open(os.path.join(FN, "ml", "models", "decision_table.json")))
NOW, LAT, LNG = 1_000_000.0, -1.2921, 36.8219
def R(i, typ, dlat): return dict(id=i, name=i, type=typ, phone="+254700000000", lat=LAT + dlat, lng=LNG, status="available", last_seen=NOW - 10, verified=True, capabilities=None)
def INC(cat, ts="pending", answers=None):
    return dict(id="INC1", code="20261021-120000-X-AB12", status="Active", category=cat, subtype=None, triageStatus=ts, answers=answers or {},
                lat=LAT, lng=LNG, createdAt=NOW - 5, freeText="")
POOL = [R("A1", "Ambulance", .02), R("A2", "Ambulance", .04), R("F1", "Fire", .05)]
def creates(res): return [a["offer"] for a in res["actions"] if a["type"] == "create_offer"]
def apply(offers, res):
    offers = [dict(o) for o in offers]
    for a in res["actions"]:
        if a["type"] == "create_offer": offers.append(dict(a["offer"]))
        elif a["type"] == "update_offer": next(x for x in offers if x["id"] == a["id"]).update(a["fields"])
    return offers
n = 0
def ok(m):
    global n; n += 1; print(f"{n:2d} PASS {m}")

# 1 alert just received: the offer says its High is the default
r = core.reconcile(INC("Medical Emergency"), POOL, [], NOW, TABLE); got = creates(r)
assert got and all(o["priority"] == "High" and o["prioritySource"] == "safe_fallback" for o in got); ok("no details yet: offers are High and marked safe_fallback")

# 2 details arrive: the open offers are updated with the real source
offers = apply([], core.reconcile(INC("Road Accident"), POOL, [], NOW, TABLE))
assert all(o["prioritySource"] == "safe_fallback" for o in offers)
inc2 = INC("Road Accident", ts="quick", answers={"conscious": "No", "trapped": "No", "hazard": "No"})
expected = core.server_priority(inc2, TABLE)["source"]; print("   source after answers:", expected)
r2 = core.reconcile(inc2, POOL, offers, NOW + 3, TABLE); ups = [a for a in r2["actions"] if a["type"] == "update_offer"]
assert ups and all(u["fields"].get("prioritySource", "safe_fallback") == expected for u in ups); ok("answers arrive: open offers get the real priority source")
if expected != "safe_fallback":
    assert all(u["fields"].get("prioritySource") == expected for u in ups); ok("the default-High marker is replaced, not left behind")

# 3 an alert that is already assessed creates offers with its own source
inc3 = INC("Road Accident", ts="quick", answers={"conscious": "No", "trapped": "No", "hazard": "No"})
got = creates(core.reconcile(inc3, POOL, [], NOW, TABLE)); assert got and all(o["prioritySource"] == core.server_priority(inc3, TABLE)["source"] for o in got); ok("assessed alert: offers carry the assessed source")

# 4 running again changes nothing
offers = apply([], core.reconcile(INC("Medical Emergency"), POOL, [], NOW, TABLE))
r4 = core.reconcile(INC("Medical Emergency"), POOL, offers, NOW + 1, TABLE)
assert not creates(r4) and not [a for a in r4["actions"] if a["type"] == "update_offer"]; ok("idempotent: no new offers, no pointless updates")
print("\nALL OFFER PRIORITY SOURCE TESTS PASSED")
