"""Turn-by-turn steps from the Routes API. Run from the functions folder:   py tests\test_route_steps.py"""
import json, os, sys
HERE = os.path.dirname(os.path.abspath(__file__)); FN = os.path.dirname(HERE)
sys.path.insert(0, FN)
import dispatch                                   # noqa: F401
from dispatch import routes

n = 0
def ok(m):
    global n; n += 1; print(f"{n:2d} PASS {m}")

def leg(*steps): return {"legs": [{"steps": list(steps)}]}
def step(text="Head north", man="STRAIGHT", dist=120, dur="15s", poly="_p~iF~ps|U_ulLnnqC"):
    s = {"navigationInstruction": {"maneuver": man, "instructions": text}, "distanceMeters": dist, "staticDuration": dur}
    if poly is not None: s["polyline"] = {"encodedPolyline": poly}
    return s
BASE = {"duration": "300s", "distanceMeters": 2500, "polyline": {"encodedPolyline": "OVERVIEW"}}

def fake(response):
    calls = []
    def http(url, key, mask, body):
        calls.append({"url": url, "mask": mask, "body": body}); return {"routes": [response]}
    return http, calls

# 1 the old behaviour is untouched when steps are not asked for
http, calls = fake({**BASE, **leg(step())})
r = routes.route("K", (-1.29, 36.82), (-1.28, 36.82), http)
assert r == {"polyline": "OVERVIEW", "durationS": 300.0, "distanceM": 2500}, r
assert calls[0]["mask"] == "routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline" and "polylineQuality" not in calls[0]["body"]; ok("without steps: same request, same answer as before")

# 2 with steps: bigger field mask, high-quality line, steps returned
http, calls = fake({**BASE, **leg(step("Turn <b>left</b> onto <b>Waiyaki Way</b><div>Pass Safaricom</div>", "TURN_LEFT", 800, "95s", "AAA"), step("Continue", "STRAIGHT", 1700, "205s", "BBB"))})
r = routes.route("K", (-1.29, 36.82), (-1.28, 36.82), http, steps=True)
assert "routes.legs.steps.navigationInstruction" in calls[0]["mask"] and "routes.legs.steps.polyline.encodedPolyline" in calls[0]["mask"]
assert calls[0]["body"]["polylineQuality"] == "HIGH_QUALITY"
assert r["polyline"] == "OVERVIEW" and r["durationS"] == 300.0 and r["distanceM"] == 2500; ok("with steps: asks Google for the step lines and still returns the old fields")
s0 = r["steps"][0]
assert s0["instruction"] == "Turn left onto Waiyaki Way Pass Safaricom"; ok("HTML tags are removed and spaces tidied")
assert s0["maneuver"] == "turn-left" and s0["distanceM"] == 800 and s0["durationSec"] == 95; ok("maneuver, distance and time are converted for the app")
assert s0["polyline"] == "AAA" and r["steps"][1]["polyline"] == "BBB"; ok("each step's own full-precision line is passed through unchanged")
assert "stepsTruncated" not in r; ok("a short route is not marked truncated")

# 3 entities and length
assert routes.clean_instruction("Turn right onto Tom &amp; Jerry St &#39;A&#39;") == "Turn right onto Tom & Jerry St 'A'"; ok("HTML entities are decoded")
assert len(routes.clean_instruction("x" * 500)) == 120; ok("an instruction is cut at 120 characters")
assert routes.clean_instruction(None) == "" and routes.clean_instruction("a < b and c") == "a < b and c"; ok("missing text and a lone < are safe")

# 4 120-step cap
many = leg(*[step(f"Step {i}", "STRAIGHT", 10, "2s", "ZZZ") for i in range(130)])
http, _ = fake({**BASE, **many}); r = routes.route("K", (-1.29, 36.82), (-1.28, 36.82), http, steps=True)
assert len(r["steps"]) == 120 and r["stepsTruncated"] is True and all(s["polyline"] is None for s in r["steps"]); ok("more than 120 steps: first 120 kept, flagged, and no per-step lines")
http, _ = fake({**BASE, **leg(*[step("s", "STRAIGHT", 10, "2s", "ZZZ") for i in range(120)])}); r = routes.route("K", (-1.29, 36.82), (-1.28, 36.82), http, steps=True)
assert len(r["steps"]) == 120 and "stepsTruncated" not in r and r["steps"][0]["polyline"] == "ZZZ"; ok("exactly 120 steps is not truncated")

# 5 missing pieces never raise
http, _ = fake({**BASE, "legs": [{"steps": [{}, {"navigationInstruction": {}}, {"distanceMeters": "bad"}, "junk", None]}]})
r = routes.route("K", (-1.29, 36.82), (-1.28, 36.82), http, steps=True)
assert len(r["steps"]) == 3 and r["steps"][0] == {"instruction": "", "maneuver": None, "distanceM": None, "durationSec": None, "polyline": None}; ok("missing or odd fields give nulls, not errors")
http, _ = fake({**BASE}); r = routes.route("K", (-1.29, 36.82), (-1.28, 36.82), http, steps=True)
assert r["steps"] == [] and r["polyline"] == "OVERVIEW"; ok("a route with no steps still returns the overview")
assert routes.normalize_steps(None) == {"steps": []} and routes.normalize_steps("x") == {"steps": []}; ok("garbage legs give an empty list")

# 6 maneuver names
for g, w in (("TURN_SLIGHT_RIGHT", "turn-slight-right"), ("UTURN_LEFT", "uturn-left"), ("ROUNDABOUT_RIGHT", "roundabout-right"), ("RAMP_LEFT", "ramp-left"),
             ("FORK_RIGHT", "fork-right"), ("MERGE", "merge"), ("DEPART", None), ("NAME_CHANGE", None), ("FERRY", None), (None, None)):
    assert routes.normalize_steps(leg(step("x", g))["legs"])["steps"][0]["maneuver"] == w, g
ok("Google maneuver names map to the names the app understands; unknown ones become null")

# 7 failures stay quiet
def boom(url, key, mask, body): raise RuntimeError("down")
assert routes.route("K", (-1.29, 36.82), (-1.28, 36.82), boom, steps=True) is None and routes.route(None, (1, 1), (2, 2), boom, steps=True) is None; ok("Google down or no key: None, as before")

# 8 the callable, when firebase_functions is installed here
try:
    import phase3c_functions as p3
except Exception as e:                            # noqa: BLE001
    print("   (skipped the callable checks: %s)" % type(e).__name__)
else:
    http, calls = fake({**BASE, **leg(step("Go", "TURN_RIGHT", 50, "5s", "QQQ"))})
    old = p3.directions("K", (-1.29, 36.82), (-1.28, 36.82), http)
    assert old == {"ok": True, "polyline": "OVERVIEW", "etaS": 300.0, "distanceM": 2500, "estimate": False} and "steps" not in old; ok("help_directions without steps: exactly the old answer")
    new = p3.directions("K", (-1.29, 36.82), (-1.28, 36.82), http, steps=True)
    assert new["steps"][0]["maneuver"] == "turn-right" and new["overviewPolyline"] == "OVERVIEW" and new["durationSec"] == 300 and new["polyline"] == "OVERVIEW"; ok("help_directions with steps: old fields plus steps and overviewPolyline")
    est = p3.directions(None, (-1.29, 36.82), (-1.28, 36.82), None, steps=True)
    assert est["estimate"] is True and "steps" not in est; ok("no key: straight-line estimate, no steps, no error")
print("\nALL ROUTE STEP TESTS PASSED")
