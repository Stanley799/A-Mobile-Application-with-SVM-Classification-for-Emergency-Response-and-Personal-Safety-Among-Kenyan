"""Scores the text path on a labelled CSV.  Default: data/text_dev_set.csv.  Real messages: py scripts\\evaluate_text.py data\\real_messages.csv"""
import sys, os, csv
import triage_core as t
from text_triage import triage_text

path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(t.ROOT, "data", "text_dev_set.csv")
rows = list(csv.DictReader(open(path, encoding="utf-8")))
def run(label, **kw):
    n = len(rows); decided = right = wrong = unclear_ok = 0; fl_tp = fl_fn = fl_fp = 0; fails = []
    for r in rows:
        out = triage_text(r["text"], **kw); exp = r["expected_category"] or None; ef = r["expected_flag"] or None
        want_sub = {"self_harm": "mental_health_crisis"}.get(ef, ef)          # flag name -> subtype name
        if ef:
            if out["subtype"] == want_sub and out["method"] == "safety_flag": fl_tp += 1
            else: fl_fn += 1; fails.append(("FLAG MISSED", r["text"], ef, out["subtype"]))
        elif out["subtype"] in ("sexual_violence", "mental_health_crisis", "domestic_violence") and out["method"] == "safety_flag": fl_fp += 1; fails.append(("FALSE FLAG", r["text"], "", out["subtype"]))
        if out["category"] is None:
            if exp is None: unclear_ok += 1
            continue
        decided += 1
        if out["category"] == exp: right += 1
        else: wrong += 1; fails.append(("WRONG", r["text"], exp, out["category"]))
    print(f"{label:22s} messages {n} | decided {decided} | correct {right} | wrong {wrong} | correctly unclear {unclear_ok} | flags found {fl_tp}/{fl_tp+fl_fn}, false flags {fl_fp}")
    return fails
run("lexicon only", use_classifier=False); run("classifier only", use_lexicon=False)
fails = run("combined (used)")
for f in fails: print("   ", f)
