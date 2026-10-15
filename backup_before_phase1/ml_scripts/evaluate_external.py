"""External stress test: run the text engine on a PUBLIC disaster-message dataset it has never seen.

It answers two questions with real, independent text:
  1. FALSE FLAGS - how often does a self-harm / sexual-violence / domestic-violence flag fire? You read the examples and judge
     whether each hit is a genuine mention (fine) or a mistake (bug to fix).
  2. CATEGORY FIT - on messages whose public labels map cleanly onto OUR categories, how many does it decide, and how many of those are right?

DATA (not included in the project; download it yourself and check its terms before reusing it):
  "Disaster Response Messages" (Appen), 26,248 English-translated messages with 36 labels.
    Option A (Hugging Face):  community-datasets/disaster_response_messages  -> save the train split as a CSV or parquet
    Option B (a GitHub copy used for testing): disaster_messages.csv + disaster_categories.csv (the 2-file layout)
RUN:
  py scripts\\evaluate_external.py --file path\\to\\messages.csv            (one file with message, genre and 0/1 label columns)
  py scripts\\evaluate_external.py --messages disaster_messages.csv --categories disaster_categories.csv
Options: --genres direct,social (default) or direct,social,news   --show 12 (examples printed per flag)
Only counts are saved (docs/external_eval_summary.txt); the dataset's text is never written to your project.

IMPORTANT: the labels describe DISASTER-RELIEF messages (food, tents, medicine), not individual 999-style emergencies, so category
accuracy here is a stress test and a vocabulary-gap finder, NOT a measure of how good the app is. Do not tune the lexicon to chase it."""
import os, sys, argparse
import pandas as pd
import triage_core as t
import text_triage as x

MAP = [("medical_help", "Medical Emergency"), ("fire", "Fire & Rescue"), ("security", "Security Threat")]   # unambiguous matches only


def load(a):
    if a.file:
        p = a.file
        df = pd.read_parquet(p) if p.lower().endswith(".parquet") else pd.read_csv(p, encoding="utf-8-sig")
    elif a.messages and a.categories:
        m = pd.read_csv(a.messages, encoding="utf-8-sig").drop_duplicates("id")
        c = pd.read_csv(a.categories, encoding="utf-8-sig").drop_duplicates("id")
        parts = c.categories.str.split(";", expand=True)
        names = [s.rsplit("-", 1)[0] for s in parts.iloc[0]]
        parts = parts.apply(lambda col: col.str.rsplit("-", n=1).str[1].astype(int))
        parts.columns = names
        parts["id"] = c.id.values
        df = m.merge(parts, on="id")
    else:
        sys.exit(__doc__)
    need = {"message", "genre", "related"} | {k for k, _ in MAP}
    if need - set(df.columns):
        sys.exit(f"Missing columns: {sorted(need - set(df.columns))}. Found: {list(df.columns)[:12]} ...")
    return df[df.related != 2].copy()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--file"); ap.add_argument("--messages"); ap.add_argument("--categories")
    ap.add_argument("--genres", default="direct,social"); ap.add_argument("--show", type=int, default=12)
    a = ap.parse_args()
    d = load(a)
    genres = {g.strip() for g in a.genres.split(",")}
    d = d[d.genre.isin(genres)].copy()
    print(f"Messages used: {len(d)} (genres: {sorted(genres)}). Running the text engine ...")
    res = [x.triage_text(s) for s in d.message.astype(str)]
    d["pred"] = [r["category"] for r in res]
    d["fl"] = [r["flags"] for r in res]
    lines = [f"messages {len(d)} genres {sorted(genres)}"]
    print("\n1. FLAGS (read each example: is it a genuine mention, or a mistake?)")
    for f in ("self_harm", "sexual_violence", "domestic_violence"):
        hit = d[d.fl.apply(lambda z: f in z)]
        print(f"\n  {f}: {len(hit)} of {len(d)} messages")
        lines.append(f"flag {f}: {len(hit)}")
        for s in hit.message.head(a.show):
            print("    -", " ".join(str(s).split())[:150])
    one = d[(d[[k for k, _ in MAP]].sum(axis=1) == 1)].copy()
    one["lab"] = one.apply(lambda r: next(n for k, n in MAP if r[k] == 1), axis=1)
    dec = one[one.pred.notna()]
    print(f"\n2. CATEGORY FIT on {len(one)} messages with exactly one mappable public label")
    print(f"  decided: {len(dec)} ({len(dec) / max(len(one), 1):.0%});  correct of decided: {(dec.pred == dec.lab).mean():.2f}")
    print("  (the rest were left 'unclear', which means the app would ask the resident - the safe outcome)")
    print(pd.crosstab(one.lab, one.pred.fillna("(unclear)")).to_string())
    lines += [f"mapped {len(one)} decided {len(dec)} correct_of_decided {(dec.pred == dec.lab).mean():.3f}"]
    out = os.path.join(t.ROOT, "docs", "external_eval_summary.txt")
    open(out, "w", encoding="utf-8").write("\n".join(lines) + "\n")
    print(f"\nSaved counts only: {out}")


if __name__ == "__main__":
    main()
