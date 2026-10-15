"""Turns a Google Forms / Microsoft Forms export into data/collected_master.csv (no retyping, no labelling by hand).

    py scripts\\import_form_export.py "C:\\path\\to\\Form responses.csv"

The form must follow docs/collection_form_guide.md (question titles start with the scenario id, e.g. "S07 ...").
The category / flag label of every message comes from data/collection_scenarios.csv, so you never label by hand.
Safe to run again after more responses arrive: rows already in the master file are skipped, nothing is overwritten.
Next step afterwards:  py scripts\\split_collected_messages.py"""
import os, re, sys, csv
import triage_core as t

DATA = os.path.join(t.ROOT, "data")
MASTER = os.path.join(DATA, "collected_master.csv")
COLS = ["scenario_id", "contributor_id", "language", "text", "consent_given", "expected_category", "expected_flag"]
LANG = {"english": "en", "en": "en", "kiswahili": "sw", "swahili": "sw", "sw": "sw", "sheng": "sheng",
        "mixed": "mixed", "a mix": "mixed", "mix": "mixed", "mixture": "mixed"}


def read(path):
    try:
        with open(path, encoding="utf-8-sig", newline="") as f:
            return list(csv.DictReader(f))
    except FileNotFoundError:
        sys.exit(f"File not found: {path}")
    except UnicodeDecodeError:
        sys.exit("The export is not UTF-8. Download it as CSV from the form (Google: Responses > Download .csv).")


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    rows = read(sys.argv[1])
    if not rows:
        sys.exit("The export has no responses.")
    heads = list(rows[0].keys())
    find = lambda word: next((h for h in heads if word in h.lower()), None)
    h_consent, h_code, h_lang = find("consent") or find("agree"), find("code"), find("language")
    h_scen = {m.group(1).upper(): h for h in heads for m in [re.match(r"^\s*(S\d{2})\b", h, re.I)] if m}
    missing = [n for n, h in (("consent", h_consent), ("code", h_code), ("language", h_lang)) if not h]
    if missing or not h_scen:
        sys.exit(f"Could not find these columns in the export: {missing or ''} {'scenario questions (titles must start with S01, S02 ...)' if not h_scen else ''}\n"
                 f"Columns found: {heads[:8]} ...\nCheck docs/collection_form_guide.md for the exact question titles.")
    scen = {r["scenario_id"]: r for r in read(os.path.join(DATA, "collection_scenarios.csv"))}
    old = read(MASTER) if os.path.exists(MASTER) else []
    have = {(r["scenario_id"], r["contributor_id"]) for r in old}
    new, notes, codes = [], [], {}
    for i, r in enumerate(rows, start=2):
        who = f"response {i - 1}"
        consent = (r.get(h_consent) or "").strip().lower()
        code = re.sub(r"\s+", "", (r.get(h_code) or "")).upper()
        lang = LANG.get((r.get(h_lang) or "").strip().lower())
        if not (consent.startswith("yes") or "agree" in consent):
            notes.append(f"{who}: no consent ticked, SKIPPED"); continue
        if not re.fullmatch(r"[A-Z]{1,3}\d{1,4}", code):
            notes.append(f"{who}: code {code!r} is not like C07, SKIPPED"); continue
        if not lang:
            notes.append(f"{who}: language {(r.get(h_lang) or '')!r} not recognised (use English / Kiswahili / Sheng / Mixed), SKIPPED"); continue
        if code in codes:
            notes.append(f"{who}: code {code} was already used in response {codes[code]}; two people sharing a code breaks the contributor split. SKIPPED")
            continue
        codes[code] = i - 1
        for sid, h in h_scen.items():
            text = " ".join((r.get(h) or "").split())
            if not text or sid not in scen or (sid, code) in have:
                continue
            new.append({"scenario_id": sid, "contributor_id": code, "language": lang, "text": text, "consent_given": "yes",
                        "expected_category": "", "expected_flag": ""})
    os.makedirs(DATA, exist_ok=True)
    write_header = not os.path.exists(MASTER) or not old and os.path.getsize(MASTER) == 0
    with open(MASTER, "a", newline="", encoding="utf-8-sig" if write_header else "utf-8") as f:
        w = csv.DictWriter(f, fieldnames=COLS)
        if write_header:
            w.writeheader()
        w.writerows(new)
    for n in notes:
        print("NOTE", n)
    people = {r["contributor_id"] for r in new}
    langs = {}
    for r in new:
        langs[r["language"]] = langs.get(r["language"], 0) + 1
    print(f"Added {len(new)} messages from {len(people)} contributors to data\\collected_master.csv (by language: {langs})")
    print("NEXT: py scripts\\split_collected_messages.py   (it checks privacy, length and labels again before splitting)")


if __name__ == "__main__":
    main()
