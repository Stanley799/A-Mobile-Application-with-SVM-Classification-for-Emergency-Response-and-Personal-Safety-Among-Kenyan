"""Compiles the trained model into a decision table covering EVERY possible set of answers, then applies the
'worse answer never lowers priority' repair. The table is what the app/Cloud Function looks up.  Run after training:
    py scripts\\build_decision_table.py"""
import os, json, numpy as np, pandas as pd, joblib
import triage_core as t

def key_of(n):
    return "|".join(str(n[f]) for f in t.FEATURES)

def build():
    model = joblib.load(os.path.join(t.ROOT, "models", "priority_classifier.joblib"))
    rows = [n for c in t.CATEGORIES for n in t.all_combinations(c)]
    D = pd.DataFrame(rows)
    P = model.predict_proba(D[t.FEATURES]); cl = list(model.classes_)
    rank = np.array([t.RANK[cl[i]] for i in P.argmax(axis=1)])
    rank = np.where(P[:, cl.index("High")] >= t.SCHEMA["high_threshold"], 2, rank)
    floor = np.array([t.RANK[t.rule_floor(r)[0]] for r in rows])
    final = np.maximum(rank, floor)
    conf = P.max(axis=1); ph = P[:, cl.index("High")]
    idx = {key_of(r): i for i, r in enumerate(rows)}
    # monotone repair: if a strictly better answer set is already at a higher priority, this one must be at least as high
    steps = []
    for i, r in enumerate(rows):
        nb = []
        for q, order in t.SCHEMA["risk_order"].items():
            if r[q] != t.NOT_ASKED and order.index(r[q]) > 0:
                r2 = dict(r); r2[q] = order[order.index(r[q]) - 1]; nb.append(idx[key_of(r2)])
        if r["people_count"] > 1:
            r2 = dict(r); r2["people_count"] -= 1; nb.append(idx[key_of(r2)])
        steps.append(nb)
    repaired = final.copy(); passes = 0; changed = True
    while changed:
        changed = False; passes += 1
        for i, nb in enumerate(steps):
            m = max([repaired[j] for j in nb], default=0)
            if m > repaired[i]:
                repaired[i] = m; changed = True
    table = {key_of(r): {"p": t.PRIORITIES[int(repaired[i])], "c": round(float(conf[i]), 3), "r": int(floor[i] < 2 and (conf[i] < t.CONFIDENCE_FLOOR or (repaired[i] < 2 and ph[i] >= t.SCHEMA["review_near_high"])))} for i, r in enumerate(rows)}
    out = {"schema_version": t.SCHEMA["version"], "feature_order": t.FEATURES, "key_format": "feature values joined by |", "entries": table}
    path = os.path.join(t.ROOT, "models", "decision_table.json")
    json.dump(out, open(path, "w"), separators=(",", ":"))
    print(f"decision table: {len(table)} entries, {os.path.getsize(path)/1e6:.2f} MB")
    print(f"repair raised {int((repaired > final).sum())} combinations (passes: {passes})")
    return rows, rank, floor, final, repaired, conf

if __name__ == "__main__":
    build()
