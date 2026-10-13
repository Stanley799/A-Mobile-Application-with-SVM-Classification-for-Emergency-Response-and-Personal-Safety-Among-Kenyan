"""Robustness tests: does the system stay SAFE when inputs are strange or files are broken?
Run:  py scripts\\test_robustness.py      (exit code 1 if any check fails)

Each check prints PASS/FAIL. They cover the failure modes listed in docs/safety_nets_and_error_handling.md."""
import os, sys, json, random, shutil, subprocess, tempfile
import triage_core as t
import text_triage as x
import predict_priority as pp
from dispatch_logic import plan_dispatch

FAILS = []
def check(name, ok, detail=""):
    print(("PASS  " if ok else "FAIL  ") + name + (f"   [{detail}]" if detail and not ok else ""))
    if not ok:
        FAILS.append(name)

REQUIRED_KEYS = {"category", "subtype", "method", "flags", "possible_flags", "needs_clarification", "requires_confirmation"}
BASE = dict(age_group="Adult", conscious="Yes", breathing="Yes", severe_bleeding="No", chest_pain="No", pregnant="No",
            trapped="No", hazard="No", weapon_involved="No", immediate_danger="No", people_count=1)

# 1. Fuzz: nothing the user types may crash the text path ------------------------------------------------------------
random.seed(7)
alphabet = "abcdefghijklmnopqrstuvwxyz ABCDEFG0123456789'.,!?-_/\\\n\t\u0000‮éü中\U0001F525’"
weird = [None, 0, 1.5, [], {}, b"bytes", "", " ", "\n\n", "!!!???", "a" * 100000, "\u0000" * 50, "\U0001F525" * 500, "fire " * 5000,
         "SELECT * FROM users;--", "<script>alert(1)</script>", "../../etc/passwd", "%s %d {0} {x}", "ñandú çarşı 火事 пожар"]
fuzz = weird + ["".join(random.choice(alphabet) for _ in range(random.randint(0, 300))) for _ in range(1500)]
bad = []
for f in fuzz:
    r = x.triage_text(f)
    if not isinstance(r, dict) or not REQUIRED_KEYS <= set(r) or r.get("method") == "error":
        bad.append(repr(f)[:40])
check(f"1. fuzz: {len(fuzz)} odd inputs, no crash, always a well-formed answer", not bad, str(bad[:3]))
check("1b. empty/None/number input asks the resident (never guesses)", all(x.triage_text(v)["needs_clarification"] for v in (None, "", "   ", 5)))

# 2. Safety flags beat everything else -------------------------------------------------------------------------------
cases = [("the house is on fire and I want to kill myself", "self_harm", "mental_health_crisis"),
         ("my husband beat me and the car crashed", None, None),          # DV wording handled below
         ("he raped me at the matatu stage", "sexual_violence", "sexual_violence"),
         ("there was an accident and I want to commit suicide", "self_harm", "mental_health_crisis")]
for msg, flag, sub in cases:
    if flag is None:
        continue
    r = x.triage_text(msg)
    check(f"2. flag wins over other content: '{msg[:45]}'", flag in r["flags"] and r["subtype"] == sub, str(r["flags"]) + str(r["subtype"]))

# 3. Idiom masks must never hide a flag ------------------------------------------------------------------------------
ign = [tm.plain for tm in x.LEX["ignore"] if tm.plain]
hidden = []
for ph in ign:
    for flag_msg, flag in (("I want to kill myself", "self_harm"), ("he raped me", "sexual_violence")):
        r = x.triage_text(f"{ph} {flag_msg}")
        if flag not in r["flags"]:
            hidden.append((ph, flag))
check(f"3. all {len(ign)} idiom masks leave self-harm and rape flags visible", not hidden, str(hidden[:3]))

# 4. Typo tolerance for flags ----------------------------------------------------------------------------------------
tests = [("I want to commit suicde", "self_harm"), ("she was molestd on the way home", "sexual_violence"), ("sucidal thoughts tonight", "self_harm")]
check("4. mistyped flag words still raise the flag", all(f in x.triage_text(m)["flags"] for m, f in tests))
check("4b. typo snapping never raises a flag on ordinary words", not any(x.triage_text(m)["flags"] for m in
      ("the building is burning near the market", "my brother was attacked by robbers", "please send an ambulance quickly", "the lorry overturned at the junction")))

# 5. Lexicon and schema agree ----------------------------------------------------------------------------------------
sch = t.SCHEMA["categories"]
errs = []
for cat, v in x.RAW.get("categories", {}).items():
    if cat not in sch:
        errs.append(f"unknown category {cat}")
        continue
    for sub in list(v.get("subtypes", {})) + list(v.get("subtype_weak", {})):
        if sub not in sch[cat]["subtypes"]:
            errs.append(f"{cat}/{sub}")
for fl, (cat, sub, floor) in x.FLAG_TARGET.items():
    if cat not in sch or sub not in sch[cat]["subtypes"] or floor not in t.PRIORITIES:
        errs.append(f"flag target {fl}")
    if fl not in x.RAW.get("flags", {}):
        errs.append(f"flag {fl} missing from lexicon")
check("5. every lexicon category, subtype and flag target exists in the schema", not errs, str(errs[:4]))

# 6. End to end: text -> category/subtype -> priority -> dispatch. Priority must never drop below the flag's floor -----
chain = [("I want to kill myself", "High"), ("he raped me", "Medium"), ("my child was kidnapped", "High"), ("my wife is being beaten by her husband", "Low")]
floor_bad = []
for msg, minimum in chain:
    r = x.triage_text(msg)
    if r["category"] is None:
        floor_bad.append((msg, "no category")); continue
    pr = pp.suggest_priority_safe({**BASE, "category": r["category"]}, subtype=r["subtype"])
    if t.RANK[pr["priority"]] < t.RANK[minimum]:
        floor_bad.append((msg, pr["priority"]))
check("6. end-to-end priority never below the safety floor", not floor_bad, str(floor_bad))

# 7. Safe fallbacks ------------------------------------------------------------------------------------------------
for name, payload in (("invalid category", {**BASE, "category": "Fire and Rescue"}), ("None payload", None), ("empty dict", {}),
                      ("bad value", {**BASE, "category": "Road Accident", "conscious": "Maybe"}), ("string payload", "help")):
    r = pp.suggest_priority_safe(payload)
    check(f"7. safe fallback on {name}: High + human review + reason", r["priority"] == "High" and r["needs_human_review"] and r["fallback_reason"])
good = pp.suggest_priority_safe({**BASE, "category": "Road Accident"})
check("7b. a valid request is not turned into a fallback", good["fallback_reason"] is None and good["priority_source"] != "safe_fallback")
saved = pp._LOAD_ERROR
pp._LOAD_ERROR = "FileNotFoundError: decision_table.json"
r = pp.suggest_priority_safe({**BASE, "category": "Road Accident"})
pp._LOAD_ERROR = saved
check("7c. decision table missing/out of date -> High + human review", r["priority"] == "High" and r["needs_human_review"])

# 8. Text classifier missing: lexicon and flags still work ---------------------------------------------------------------
saved_clf = x.CLF
x.CLF = None
r1, r2 = x.triage_text("I want to kill myself"), x.triage_text("there is a fire in the building")
x.CLF = saved_clf
check("8. text classifier missing: flags and lexicon still work", "self_harm" in r1["flags"] and r2["category"] == "Fire & Rescue")

# 9. Corrupt lexicon_user.json: system still starts and keeps safety flags (run in a scratch copy) -----------------------
tmp = tempfile.mkdtemp()
try:
    for d in ("scripts", "schema", "models"):
        shutil.copytree(os.path.join(t.ROOT, d), os.path.join(tmp, d), ignore=shutil.ignore_patterns("__pycache__"))
    open(os.path.join(tmp, "schema", "lexicon_user.json"), "w").write("{ this is not valid json ,,, ")
    code = ("import sys; sys.path.insert(0,'scripts'); import text_triage as x; r=x.triage_text('I want to kill myself'); "
            "print('OK' if 'self_harm' in r['flags'] else 'NOFLAG', len(x.LOAD_WARNINGS))")
    out = subprocess.run([sys.executable, "-c", code], cwd=tmp, capture_output=True, text=True, timeout=120)
    check("9. corrupt lexicon_user.json: loads, warns, English safety flags still work", out.stdout.startswith("OK") and not out.stdout.strip().endswith(" 0"), (out.stdout + out.stderr)[-200:])
finally:
    shutil.rmtree(tmp, ignore_errors=True)

# 10. Dispatch never crashes on an empty or odd responder pool -----------------------------------------------------------
inc = dict(id="X", lat=-1.29, lng=36.82, priority="High", subtype=None, answers=t.normalize({**BASE, "category": "Road Accident"}))
try:
    p = plan_dispatch(inc, [], 1_000_000.0)
    ok = p["show_922_always"] and p["escalate_922"] is True
except Exception as e:                                           # noqa: BLE001
    ok, p = False, repr(e)
check("10. no responders available -> 922 escalation, no crash", ok, str(p)[:120])

print("\nRESULT:", "PASS" if not FAILS else "ATTENTION -> " + "; ".join(FAILS))
sys.exit(1 if FAILS else 0)
