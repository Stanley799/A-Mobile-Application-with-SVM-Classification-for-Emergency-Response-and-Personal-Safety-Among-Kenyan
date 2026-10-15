"""Merge the proposed terms you APPROVED into schema/lexicon_user.json.   py scripts\\merge_proposed.py
Steps for you: 1) open schema\\lexicon_proposed.json and DELETE every term you disagree with,
               2) ask a native speaker about the MEDIUM ones (docs\\lexicon_review.csv),
               3) run this script, then run  py scripts\\check_lexicon.py
A timestamped backup of your file is made first; nothing is lost."""
import os
import sys
import json
import shutil
import datetime
import triage_core as t
import text_triage as T

SCHEMA = os.path.join(t.ROOT, "schema")
USER, PROP = os.path.join(SCHEMA, "lexicon_user.json"), os.path.join(SCHEMA, "lexicon_proposed.json")


def dedupe(items):
    """Remove exact duplicates, keep order (pairs are compared by their JSON text)."""
    seen, out = set(), []
    for it in items:
        k = json.dumps(it, sort_keys=True, ensure_ascii=False) if isinstance(it, dict) else str(it).strip().lower()
        if k not in seen:
            seen.add(k)
            out.append(it)
    return out


def main():
    for p in (USER, PROP):
        if not os.path.exists(p):
            sys.exit(f"File not found: {p}")
    try:
        user = json.load(open(USER, encoding="utf-8"))
        prop = json.load(open(PROP, encoding="utf-8"))
    except json.JSONDecodeError as e:
        sys.exit(f"Invalid JSON (line {e.lineno}, column {e.colno}): {e.msg}. Nothing was changed.")
    stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    shutil.copyfile(USER, os.path.join(SCHEMA, f"lexicon_user.backup_{stamp}.json"))
    merged = T.merge_raw(user, prop)
    for name, f in merged.get("flags", {}).items():
        for tier in ("strong", "weak"):
            f[tier] = dedupe(f.get(tier, []))
    for c in merged["categories"].values():
        for key in ("terms", "weak_terms"):
            c[key] = dedupe(c.get(key, []))
        for key in ("subtypes", "subtype_weak"):
            for sub in list(c.get(key, {})):
                c[key][sub] = dedupe(c[key][sub])
    for name in list(merged.get("themes", {})):
        merged["themes"][name] = dedupe(merged["themes"][name])
    for key in ("ignore_phrases", "common_words"):
        merged[key] = dedupe(merged.get(key, []))
    merged.pop("tests", None)
    merged["tests"] = user.get("tests", [])                  # tests come from your file only (merge_raw would double them)
    json.dump(merged, open(USER, "w", encoding="utf-8"), indent=1, ensure_ascii=False)
    os.replace(PROP, os.path.join(SCHEMA, f"lexicon_proposed.merged_{stamp}.json"))
    print("Merged. Your previous file was saved as lexicon_user.backup_%s.json" % stamp)
    print("The proposed file was renamed lexicon_proposed.merged_%s.json" % stamp)
    print("NEXT: run  py scripts\\check_lexicon.py  and  py scripts\\evaluate_text.py")


if __name__ == "__main__":
    main()
