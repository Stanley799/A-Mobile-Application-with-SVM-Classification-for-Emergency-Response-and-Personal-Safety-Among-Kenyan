"""Tests the finished decision table on EVERY possible set of answers (the input space is finite).
Run:  py scripts\\test_combinations.py"""
import os, json, numpy as np, pandas as pd
import triage_core as t

T = json.load(open(os.path.join(t.ROOT, "models", "decision_table.json")))
assert T["schema_version"] == t.SCHEMA["version"], "Table out of date: run build_decision_table.py"
rows = [n for c in t.CATEGORIES for n in t.all_combinations(c)]
D = pd.DataFrame(rows)
ent = [T["entries"]["|".join(str(r[f]) for f in t.FEATURES)] for r in rows]
D["final"] = [t.RANK[e["p"]] for e in ent]; D["review"] = [bool(e["r"]) for e in ent]
D["floor"] = [t.RANK[t.rule_floor(r)[0]] for r in rows]; D["ref"] = [t.RANK[t.reference_priority(r)] for r in rows]
failures = []

v = int((D.final < D.floor).sum())
print(f"1. Combinations tested: {len(D)}  (every possible set of answers)\n   Rule floor broken: {v}  (must be 0)")
if v: failures.append("floor broken")

print("\n2. Table priority versus the protocol label, per category")
print(f"   {'category':20s} {'cases':>6s} {'agree':>7s} {'High->Low':>9s} {'High->Med':>9s} {'over-triage to High':>20s} {'flagged for review':>19s}")
for cat, g in D.groupby("category"):
    hl = int(((g.ref == 2) & (g.final == 0)).sum()); hm = int(((g.ref == 2) & (g.final == 1)).sum()); ov = int(((g.ref < 2) & (g.final == 2)).sum())
    print(f"   {cat:20s} {len(g):6d} {(g.ref == g.final).mean():7.3f} {hl:9d} {hm:9d} {ov:20d} {g.review.mean():19.3f}")
hl_all = int(((D.ref == 2) & (D.final == 0)).sum()); hm_all = D[(D.ref == 2) & (D.final == 1)]
print(f"   Total High->Low: {hl_all} (must be 0). Total High->Medium: {len(hm_all)}, of which flagged for human review: {int(hm_all.review.sum())} ({hm_all.review.mean():.0%})")
if hl_all: failures.append(f"{hl_all} High->Low")
under = int((D.final < D.ref).sum())
print(f"   Under-triage versus protocol (any level): {under} (must be 0, protocol guard)")
if under: failures.append(f"{under} under-triage vs protocol")

key = {tuple(r[f] for f in t.FEATURES): i for i, r in enumerate(D[t.FEATURES].to_dict("records"))}
viol = []
for i, r in enumerate(D[t.FEATURES].to_dict("records")):
    steps = [(q, order[order.index(r[q]) + 1]) for q, order in t.SCHEMA["risk_order"].items() if r[q] != t.NOT_ASKED and order.index(r[q]) + 1 < len(order)]
    if r["people_count"] < 5: steps.append(("people_count", r["people_count"] + 1))
    for q, nv in steps:
        r2 = dict(r); r2[q] = nv; k = key.get(tuple(r2[f] for f in t.FEATURES))
        if k is not None and D.final.iloc[k] < D.final.iloc[i]:
            viol.append((r["category"], q, r[q], nv, t.PRIORITIES[D.final.iloc[i]], t.PRIORITIES[D.final.iloc[k]]))
print(f"\n3. Monotonic check (a worse answer lowers the priority): {len(viol)} violations (must be 0)")
if viol: failures.append(f"{len(viol)} monotonic violations")

os.makedirs(os.path.join(t.ROOT, "docs"), exist_ok=True)
out = D.copy(); out["final_priority"] = [t.PRIORITIES[i] for i in D.final]; out["protocol_priority"] = [t.PRIORITIES[i] for i in D.ref]
out.drop(columns=["floor", "ref", "final"]).to_csv(os.path.join(t.ROOT, "docs", "all_combinations_results.csv"), index=False)
print("\nSaved docs/all_combinations_results.csv (open in Excel to inspect any combination)")
print("RESULT:", "PASS" if not failures else "ATTENTION -> " + "; ".join(failures))
