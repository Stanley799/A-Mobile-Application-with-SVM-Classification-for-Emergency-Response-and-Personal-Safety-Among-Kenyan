import json, os, pandas as pd
import triage_core as t
S = t.SCHEMA; meta = json.load(open(os.path.join(t.ROOT, "models", "metadata.json")))
res = pd.read_csv(os.path.join(t.ROOT, "docs", "all_combinations_results.csv"))
ordr = {"Low": 0, "Medium": 1, "High": 2}
cat_rows = []
for c, g in res.groupby("category"):
    r, f = g.protocol_priority.map(ordr), g.final_priority.map(ordr)
    cat_rows.append([c, len(g), f"{(r == f).mean():.1%}", int(((r == 2) & (f == 0)).sum()), int(((r == 2) & (f == 1)).sum()), int(((r < 2) & (f == 2)).sum()), f"{g.review.mean():.1%}"])
W = []
for c, v in S["weights"]["baseline"].items(): W.append(["Starting score", c, v["value"], v["basis"], v["note"]])
for q, tb in S["weights"]["answers"].items():
    for val, v in tb.items(): W.append([q, val, v["value"], v["basis"], v["note"]])
for k, v in S["weights"]["people_count"].items(): W.append(["people_count", k + (" or more" if k == "5" else ""), v["value"], v["basis"], v["note"]])
out = {"version": S["version"], "meta": {k: meta[k] for k in ("model", "trained_rows", "python", "sklearn", "pandas")}, "cv": meta["cv_summary"],
       "weights": W, "floors": [[f["id"], f.get("category") or f.get("subtype") or "any", f["reason"], f["floor"]] for f in S["floors"]],
       "questions": [[k, v["type"], v["prompt"], ", ".join(v.get("values", [])) or f"{v.get('min')} to {v.get('max')}", json.dumps(v.get("ask_if", ""))] for k, v in S["questions"].items()],
       "categories": [[c, ", ".join(v["questions"]), ", ".join(v["subtypes"])] for c, v in S["categories"].items()],
       "combo_rows": cat_rows, "total_combos": len(res), "routing": S["routing"], "hotlines": S["hotlines"], "thresholds": [S["high_threshold"], S["review_near_high"], S["confidence_floor"]]}
json.dump(out, open(os.path.join(t.ROOT, "docs", "doc_data.json"), "w"), indent=1)
print("ok", len(W), "weights rows")
