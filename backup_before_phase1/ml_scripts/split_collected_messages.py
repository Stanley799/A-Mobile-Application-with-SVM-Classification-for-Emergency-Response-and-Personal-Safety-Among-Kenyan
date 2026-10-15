"""Splits the messages you collected into the TRAINING file and the EXAM file, safely.
    py scripts\\split_collected_messages.py                      (reads data\\collected_master.csv)
    py scripts\\split_collected_messages.py --exam-ids C04,C09   (choose the exam contributors yourself)
    py scripts\\split_collected_messages.py --exam-share 0.4     (about 40% of the messages go to the exam)

WHY THIS SCRIPT EXISTS
  * The split is BY CONTRIBUTOR, never by message. One person's writing style must not appear in both files,
    otherwise the exam is easier than real life.
  * Labels come from the scenario you gave (expected_category / expected_flag), so nobody labels a message by looking at the model's answer.
  * It refuses messages without consent, with phone numbers or e-mails, empty or over-long, with unknown labels, or duplicated.
  * It never overwrites a file that already holds data unless you pass --force.
Master columns: scenario_id, contributor_id, language, text, consent_given, expected_category, expected_flag
(expected_* may be left empty when scenario_id is given: they are copied from data\\collection_scenarios.csv)."""
import os
import re
import sys
import csv
import random
import argparse
import triage_core as t

DATA = os.path.join(t.ROOT, "data")
HEADER = ["text", "language", "expected_category", "expected_flag", "contributor_id", "consent_given"]
FLAGS = {"", "self_harm", "sexual_violence", "domestic_violence"}
LANGS = {"en", "sw", "sheng", "mixed"}
YES = {"yes", "y", "true", "1"}
PHONE = re.compile(r"(\+?254|\b0)\s?[17]\d{2}[\s-]?\d{3}[\s-]?\d{3}\b")
EMAIL = re.compile(r"[\w.+-]+@[\w-]+\.[\w.]+")


def read_csv(path):
    """Read a CSV written by Excel (UTF-8 with or without BOM). Clear message instead of a crash."""
    try:
        with open(path, encoding="utf-8-sig", newline="") as f:
            return list(csv.DictReader(f))
    except FileNotFoundError:
        sys.exit(f"File not found: {path}")
    except UnicodeDecodeError:
        sys.exit(f"{path} is not UTF-8. In Excel use: Save As > CSV UTF-8 (Comma delimited).")


def has_data(path):
    """True when a target CSV already holds at least one data row."""
    return os.path.exists(path) and len(read_csv(path)) > 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--master", default=os.path.join(DATA, "collected_master.csv"))
    ap.add_argument("--exam-share", type=float, default=0.3)
    ap.add_argument("--exam-ids", default="")
    ap.add_argument("--force", action="store_true")
    a = ap.parse_args()
    out_train, out_exam = os.path.join(DATA, "text_training_user.csv"), os.path.join(DATA, "real_messages.csv")
    if not a.force and (has_data(out_train) or has_data(out_exam)):
        sys.exit("text_training_user.csv or real_messages.csv already has data. Nothing was changed. Use --force only if you are sure.")
    scen = {r["scenario_id"]: r for r in read_csv(os.path.join(DATA, "collection_scenarios.csv"))}
    rows, problems, seen = [], [], {}
    for i, r in enumerate(read_csv(a.master), start=2):
        who = f"row {i}"
        text = " ".join((r.get("text") or "").split())
        cid = (r.get("contributor_id") or "").strip()
        lang = (r.get("language") or "").strip().lower()
        cat = (r.get("expected_category") or "").strip()
        flag = (r.get("expected_flag") or "").strip()
        sid = (r.get("scenario_id") or "").strip()
        if sid:
            if sid not in scen:
                problems.append(f"{who}: unknown scenario_id {sid!r}"); continue
            cat = cat or scen[sid]["expected_category"]
            flag = flag or scen[sid]["expected_flag"]
        if (r.get("consent_given") or "").strip().lower() not in YES:
            problems.append(f"{who}: no consent, SKIPPED"); continue
        if not text or len(text) > 280:
            problems.append(f"{who}: text empty or longer than 280 characters, skipped"); continue
        if PHONE.search(text) or EMAIL.search(text):
            problems.append(f"{who}: contains a phone number or e-mail (privacy), skipped. Remove it and run again"); continue
        if not re.fullmatch(r"[A-Za-z]{1,3}\d{1,4}", cid):
            problems.append(f"{who}: contributor_id {cid!r} must be a code like C07 (never a name), skipped"); continue
        if lang not in LANGS:
            problems.append(f"{who}: language {lang!r} must be one of {sorted(LANGS)}, skipped"); continue
        if cat and cat not in t.CATEGORIES:
            problems.append(f"{who}: unknown expected_category {cat!r}, skipped"); continue
        if flag not in FLAGS:
            problems.append(f"{who}: unknown expected_flag {flag!r}, skipped"); continue
        key = re.sub(r"\W+", " ", text.lower()).strip()
        if key in seen:
            problems.append(f"{who}: same text as row {seen[key]}, skipped"); continue
        seen[key] = i
        rows.append({"text": text, "language": lang, "expected_category": cat, "expected_flag": flag, "contributor_id": cid, "consent_given": "yes"})
    for p in problems:
        print("NOTE", p)
    if not rows:
        sys.exit("No usable rows. Nothing written.")
    by = {}
    for r in rows:
        by.setdefault(r["contributor_id"], []).append(r)
    ids = sorted(by)
    if a.exam_ids:
        exam_ids = {x.strip() for x in a.exam_ids.split(",") if x.strip()}
        missing = exam_ids - set(ids)
        if missing:
            sys.exit(f"exam ids not found in the data: {sorted(missing)}")
    else:
        rnd = random.Random(42)
        order = ids[:]
        rnd.shuffle(order)
        target, exam_ids, n = a.exam_share * len(rows), set(), 0
        for c in order:
            if n >= target:
                break
            exam_ids.add(c)
            n += len(by[c])
    exam = [r for c in ids if c in exam_ids for r in by[c]]
    train = [r for c in ids if c not in exam_ids for r in by[c]]
    if not train or not exam:
        sys.exit("A split needs at least 2 contributors (one for training, one for the exam). Nothing written.")
    for path, part in ((out_train, train), (out_exam, exam)):
        with open(path, "w", encoding="utf-8", newline="") as f:
            w = csv.DictWriter(f, fieldnames=HEADER)
            w.writeheader()
            w.writerows(part)
    print(f"\nContributors: {len(ids)} | usable messages: {len(rows)}")
    print(f"TRAINING  text_training_user.csv : {len(train)} messages from {len(ids) - len(exam_ids)} contributors")
    print(f"EXAM      real_messages.csv      : {len(exam)} messages from {len(exam_ids)} contributors ({sorted(exam_ids)})")
    for name, part in (("exam", exam), ("training", train)):
        cats, flags = {}, {}
        for r in part:
            k = r["expected_category"] or "(unclear)"
            cats[k] = cats.get(k, 0) + 1
            if r["expected_flag"]:
                flags[r["expected_flag"]] = flags.get(r["expected_flag"], 0) + 1
        print(f"  {name} by category: {dict(sorted(cats.items()))} | safety flags: {flags or 'none'}")
        thin = [c for c in t.CATEGORIES if cats.get(c, 0) < 3]
        if name == "exam" and thin:
            print(f"  WARNING: fewer than 3 exam messages for {thin}: the exam says little about them. Collect more or choose other exam contributors.")
    print("\nNEXT: py scripts\\train_text_classifier.py   then   py scripts\\evaluate_text.py data\\real_messages.csv")


if __name__ == "__main__":
    main()
