r"""Scores the text path on a labelled CSV, by split / language / category.
  py scripts\eval_text_multi.py data\text_eval_sw.csv [--classifier] [--split holdout] [--show]
Columns: text,language,expected_category,expected_flag[,split].
  top1    the suggested category is the right one
  chips   the right category is the suggestion OR one of the alternatives shown as chips
  wrong   a category was suggested and it is not the expected one (the harmful case)
  unclr   no category suggested (the resident is asked)
  none_ok/none_bad  rows where NO category was expected (chit-chat): correctly left unclear / wrongly classified
  flags   safety flags found / missed / falsely raised"""
import sys, csv, os, collections
import triage_core as t
from text_triage import triage_text, LOAD_WARNINGS
args = [a for a in sys.argv[1:] if not a.startswith("--") and a not in ("dev", "holdout")]
path = args[0] if args else os.path.join(t.ROOT, "data", "text_eval_sw.csv")
use_clf = "--classifier" in sys.argv
only = sys.argv[sys.argv.index("--split") + 1] if "--split" in sys.argv else None
rows = [r for r in csv.DictReader(open(path, encoding="utf-8")) if (not only or r.get("split") == only)]
FLAGSUB = {"self_harm": "mental_health_crisis", "sexual_violence": "sexual_violence", "domestic_violence": "domestic_violence"}
groups = collections.defaultdict(collections.Counter); fails = []
for r in rows:
    out = triage_text(r["text"], use_classifier=use_clf)
    exp = r["expected_category"] or None; ef = r["expected_flag"] or None
    keys = ["ALL", "lang:" + r["language"], "cat:" + (exp or "(none)")] + (["flag:" + ef] if ef else [])
    got = out["category"]; chips = [c for c in [got] + list(out.get("alternatives", [])) if c]
    for k in keys:
        g = groups[k]; g["n"] += 1
        if exp is None:
            g["none_ok" if got is None and not out["flags"] else "none_bad"] += 1
        else:
            if got == exp: g["top1"] += 1
            elif got is None: g["unclear"] += 1
            else: g["wrong"] += 1
            if exp in chips: g["inchips"] += 1
        if ef:
            g["flag_ok" if (out["method"] == "safety_flag" and out["subtype"] == FLAGSUB[ef]) else "flag_miss"] += 1
        elif out["method"] == "safety_flag": g["flag_false"] += 1
    ok = (got == exp) if exp else (got is None and not out["flags"])
    if ef: ok = ok and out["method"] == "safety_flag" and out["subtype"] == FLAGSUB[ef]
    if not ok: fails.append((r["text"], r["language"], exp, ef, got, out["subtype"], out["method"], out.get("alternatives")))
print(f"{'group':30s} {'n':>4} {'top1':>5} {'chips':>6} {'wrong':>6} {'unclr':>6} | none_ok none_bad | flags ok/miss/false")
for k in sorted(groups, key=lambda x: (x != "ALL", x)):
    g = groups[k]; n = g["n"]; en = n - g["none_ok"] - g["none_bad"]
    pc = lambda v: f"{100*v/en:4.0f}%" if en else "   - "
    print(f"{k:30s} {n:4d} {pc(g['top1']):>5} {pc(g['inchips']):>6} {pc(g['wrong']):>6} {pc(g['unclear']):>6} | {g['none_ok']:7d} {g['none_bad']:8d} | {g['flag_ok']}/{g['flag_miss']}/{g['flag_false']}")
if "--show" in sys.argv:
    for f in fails: print("  FAIL", f)
print("failures:", len(fails), "of", len(rows), "| classifier:", "on" if use_clf else "off", "| load warnings:", len(LOAD_WARNINGS))
