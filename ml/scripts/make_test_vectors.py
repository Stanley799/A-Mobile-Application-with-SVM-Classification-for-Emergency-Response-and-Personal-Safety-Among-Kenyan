"""Writes integration/test_vectors.json: answer sets with the priority the PYTHON system gives (suggest_priority_safe).
The Dart test (integration/triage_parity_test.dart) must give the same answers; that proves the app and the model agree.
Also self-checks a Python mirror of the Dart logic against the same vectors."""
import os, json, random
import triage_core as t
import predict_priority as pp

random.seed(11)
SUBS = {c: [None] + list(v["subtypes"]) for c, v in t.SCHEMA["categories"].items()}
vectors = []
for cat in t.CATEGORIES:
    combos = list(t.all_combinations(cat))
    for ans in random.sample(combos, min(60, len(combos))):
        for sub in random.sample(SUBS[cat], min(3, len(SUBS[cat]))):
            payload = {**ans, "category": cat}
            r = pp.suggest_priority_safe(payload, sub)
            vectors.append({"category": cat, "subtype": sub, "answers": {k: str(v) for k, v in ans.items() if k != "category"},
                            "expected_priority": r["priority"], "expected_review": r["needs_human_review"]})
# the two subtype floors must be present in the vectors
for cat, sub in (("Security Threat", "sexual_violence"), ("Other / General", "mental_health_crisis")):
    if cat in SUBS and sub in SUBS[cat]:
        for ans in random.sample(list(t.all_combinations(cat)), 25):
            r = pp.suggest_priority_safe({**ans, "category": cat}, sub)
            vectors.append({"category": cat, "subtype": sub, "answers": {k: str(v) for k, v in ans.items() if k != "category"},
                            "expected_priority": r["priority"], "expected_review": r["needs_human_review"]})
json.dump({"schema_version": t.SCHEMA["version"], "vectors": vectors}, open(os.path.join(t.ROOT, "integration", "test_vectors.json"), "w"), indent=0)

# Python mirror of the Dart lookup (same steps as dart/triage_lookup.dart) -> must equal the vectors
T = pp._TABLE["entries"]; FLO = {f["subtype"]: f["floor"] for f in t.SCHEMA["floors"] if "subtype" in f and not f.get("when")}
def mirror(cat, ans, sub):
    parts = [cat if f == "category" else ans.get(f, "1" if f == "people_count" else t.SCHEMA["not_asked"]) for f in t.FEATURES]
    e = T["|".join(parts)]; pr, rv = e["p"], bool(e["r"]); fl = FLO.get(sub)
    if fl and t.RANK[fl] > t.RANK[pr]: pr = fl
    if fl == "High" or pr == "High": rv = False
    return pr, rv
# exhaustive: EVERY answer combination x EVERY subtype of its category (about 112,000 cases), not just the stored sample
n_all = bad_all = 0
for cat in t.CATEGORIES:
    for ans in t.all_combinations(cat):
        a = {k: str(v) for k, v in ans.items() if k != "category"}
        for sub in [None] + list(t.SCHEMA["categories"][cat]["subtypes"]):
            r = pp.suggest_priority_safe({**ans, "category": cat}, sub)
            n_all += 1
            if mirror(cat, a, sub) != (r["priority"], r["needs_human_review"]):
                bad_all += 1
print(f"exhaustive: {n_all} combination x subtype cases; Dart-logic mirror disagrees on {bad_all}")
bad = [v for v in vectors if mirror(v["category"], v["answers"], v["subtype"]) != (v["expected_priority"], v["expected_review"])]
print(f"{len(vectors)} vectors written; Dart-logic mirror disagrees on {len(bad)}")
if bad: print(bad[:3])
raise SystemExit(1 if (bad or bad_all) else 0)
