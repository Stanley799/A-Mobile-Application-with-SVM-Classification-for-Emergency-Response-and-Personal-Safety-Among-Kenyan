"""Native-speaker review sheet for the lexicon.

STEP 1  py scripts\\review_sheet.py make     -> writes docs\\native_review_sheet.csv  (open it in Excel)
STEP 2  In Excel fill the column YOUR_DECISION on EVERY row with:  keep  |  remove  |  change
        (for 'change' also type the new term in REPLACEMENT; keep the prefix such as v0: or vr: if the term has one).
        Save as CSV (UTF-8). Do not rename or reorder columns and do not edit the other columns.
STEP 3  py scripts\\review_sheet.py apply    -> applies your decisions to lexicon_user.json and lexicon_proposed.json
        (timestamped backups first). Then run  py scripts\\merge_proposed.py  and  py scripts\\check_lexicon.py.

A decision on a term applies EVERYWHERE that term appears in that file (category, subtype and so on)."""
import os, sys, csv, json, shutil, datetime
import triage_core as t
import text_triage as T

SCHEMA = os.path.join(t.ROOT, "schema")
FILES = {"user": os.path.join(SCHEMA, "lexicon_user.json"), "proposed": os.path.join(SCHEMA, "lexicon_proposed.json")}
SHEET = os.path.join(t.ROOT, "docs", "native_review_sheet.csv")
COLS = ["id", "file", "where_it_is_used", "term", "meaning_or_note", "why_you_are_asked", "YOUR_DECISION", "REPLACEMENT"]

# plain-English meanings of the assistant's PROPOSED terms (standard Kiswahili; Kenyan usage still needs YOUR confirmation)
GLOSS = {
 "vr:nyonga": "kujinyonga = to hang oneself", "vr:dhuru": "kujidhuru = to harm oneself", "vr:toa uhai": "kujitoa uhai = to take one's own life",
 "sitaki kuishi": "I do not want to live", "hataki kuishi": "he/she does not want to live", "afadhali nife": "I would rather die",
 "afadhali afe": "he/she would rather die", "nimechoka na maisha": "I am tired of life", "sina matumaini": "I have no hope",
 "v0:kata tamaa": "to give up hope", "ubakaji": "rape", "mbakaji": "a rapist", "wabakaji": "rapists",
 "unyanyasaji wa kingono": "sexual abuse / harassment", "v0:lazimishwa kufanya ngono": "was forced to have sex",
 "unyanyasaji wa nyumbani": "abuse at home", "vurugu za nyumbani": "violence at home",
 "v0:jifungua": "to give birth", "chakula kimekwama kooni": "food is stuck in the throat (choking)", "v0:umwa": "to be in pain / unwell",
 "mjamzito": "pregnant woman", "ajali ya moto": "fire accident", "v0:ungua": "to burn", "kifusi": "rubble",
 "mob justice": "English term used in Kenya", "v:iba": "to steal", "umati": "crowd", "uhalifu": "crime",
 "msongo wa mawazo": "mental strain / depression", "sonona": "depression", "mfadhaiko": "distress / stress / anxiety",
 "v0:vunjika moyo": "to be heartbroken", "upweke": "loneliness", "vx:acha": "to leave / break up with someone",
 "v0:achana": "to separate / break up", "talaka": "divorce", "mpenzi": "lover / partner", "mtihani": "exam", "ada": "school fees",
 "matokeo": "results", "deni": "debt", "madeni": "debts", "mkopo": "loan", "kodi": "rent / tax", "v0:futwa kazi": "to be sacked",
 "ukosefu wa kazi": "unemployment", "wazazi": "parents", "familia": "family", "msiba": "bereavement", "mazishi": "funeral",
 "kifo": "death", "baada ya kujifungua": "after giving birth", "mtoto mchanga": "newborn baby", "pombe": "alcohol",
 "v0:lewa": "to get drunk", "ulevi": "drunkenness", "dawa za kulevya": "illegal drugs", "v0:onewa": "to be treated unfairly / bullied",
 "vx:onea": "to treat someone unfairly / bully"}

def where_label(path):
    return path

def iter_lists(data):
    """Yield (path, list_object) for every term list in a lexicon dict (flags, categories, subtypes, themes, ignore_phrases)."""
    for name, f in data.get("flags", {}).items():
        if isinstance(f, list):
            yield f"flags.{name} strong", f
        elif isinstance(f, dict):
            for tier in ("strong", "weak"):
                if tier in f:
                    yield f"flags.{name} {tier}", f[tier]
    for cat, c in data.get("categories", {}).items():
        for key, lab in (("terms", "strong"), ("weak_terms", "weak")):
            if key in c:
                yield f"{cat} {lab}", c[key]
        for key, lab in (("subtypes", "strong"), ("subtype_weak", "weak")):
            for sub, lst in c.get(key, {}).items():
                yield f"{cat} / {sub} {lab}", lst
    for name, lst in data.get("themes", {}).items():
        yield f"theme: {name}", lst
    if "ignore_phrases" in data:
        yield "ignore (never counts)", data["ignore_phrases"]

def item_key(it):
    if isinstance(it, dict):
        return "PAIR:" + json.dumps(it, sort_keys=True, ensure_ascii=False)
    return T.Term(it).key

def item_label(it):
    if isinstance(it, dict):
        p = it["pair"]
        return "WHO: " + " | ".join(p["who"]) + "   +   ACT: " + " | ".join(p["act"]) + f"   (within {p.get('window', 8)} words)"
    return str(it)

def load(which):
    return json.load(open(FILES[which], encoding="utf-8"))

def review_rows():
    """Which terms need a native check: every proposed term and pair, plus the owner's terms flagged native_check=yes."""
    import pandas as pd
    rev = pd.read_csv(os.path.join(t.ROOT, "docs", "lexicon_review.csv"))
    all_reviewed = set(rev.term.astype(str))
    ask_user = {}
    for _, r in rev[(rev.native_check == "yes") & (rev.file == "lexicon_user.json")].iterrows():
        ask_user[str(r.term)] = (str(r.note), str(r.status))
    rows = []
    for which in ("user", "proposed"):
        if not os.path.exists(FILES[which]):
            continue
        seen = {}
        for path, lst in iter_lists(load(which)):
            for it in lst:
                k = item_key(it)
                seen.setdefault(k, {"item": it, "where": []})["where"].append(path)
        for k, v in seen.items():
            it = v["item"]
            if which == "user":
                nk = k if not k.startswith("PAIR:") else json.dumps(it, ensure_ascii=False)
                is_new = k not in all_reviewed and nk not in all_reviewed
                if k not in ask_user and nk not in ask_user and not is_new:
                    continue
                if is_new:
                    note, status = "new or changed since the last review", "NEW"
                    why = "you added or changed this term; please confirm it"
                else:
                    note, status = ask_user.get(k) or ask_user.get(nk)
                    why = "your term, but we could not verify it in a source" if not k.startswith("PAIR:") else "a 'who + act' rule built from your phrases"
            else:
                note, why = GLOSS.get(k, "(no gloss)"), "assistant suggestion, not in your file; active only if you keep it"
            rows.append({"file": which, "where_it_is_used": "; ".join(v["where"]), "term": item_label(it), "_key": k,
                         "meaning_or_note": note, "why_you_are_asked": why})
    return rows

def make():
    rows = review_rows()
    os.makedirs(os.path.dirname(SHEET), exist_ok=True)
    with open(SHEET, "w", newline="", encoding="utf-8-sig") as f:
        w = csv.DictWriter(f, fieldnames=COLS)
        w.writeheader()
        for i, r in enumerate(rows, 1):
            w.writerow({"id": i, "file": r["file"], "where_it_is_used": r["where_it_is_used"], "term": r["term"],
                        "meaning_or_note": r["meaning_or_note"], "why_you_are_asked": r["why_you_are_asked"], "YOUR_DECISION": "", "REPLACEMENT": ""})
    print(f"Wrote {SHEET} with {len(rows)} rows. Open it in Excel and fill YOUR_DECISION on every row (keep / remove / change).")

def apply():
    if not os.path.exists(SHEET):
        sys.exit("Sheet not found. Run:  py scripts\\review_sheet.py make")
    rows = list(csv.DictReader(open(SHEET, newline="", encoding="utf-8-sig")))
    for which, path in FILES.items():
        if any(r.get("file") == which for r in rows) and not os.path.exists(path):
            sys.exit(f"NOTHING WAS CHANGED. The sheet has '{which}' rows but this file is missing:\n  {path}\n"
                     f"Put the file back in the schema folder (copy it from the project zip) and run apply again.")
    expected = {(r["file"], r["term"]): r for r in review_rows()}
    problems, decisions = [], {}
    for r in rows:
        d = (r.get("YOUR_DECISION") or "").strip().lower()
        who = f"row {r['id']} ({r['term'][:40]})"
        if d not in ("keep", "remove", "change"):
            problems.append(f"{who}: YOUR_DECISION must be keep, remove or change (found '{d}')"); continue
        rep = (r.get("REPLACEMENT") or "").strip()
        if d == "change":
            if not rep:
                problems.append(f"{who}: 'change' needs a REPLACEMENT"); continue
            if r["term"].startswith("WHO:"):
                problems.append(f"{who}: rules with WHO/ACT cannot be changed here; choose keep or remove and edit the file by hand"); continue
            try:
                T.Term(rep)
            except Exception as e:
                problems.append(f"{who}: REPLACEMENT '{rep}' is not valid ({e})"); continue
        if (r["file"], r["term"]) not in expected:
            problems.append(f"{who}: this row does not match the files any more; run 'make' again"); continue
        decisions[(r["file"], r["term"])] = (d, rep, expected[(r["file"], r["term"])]["_key"])
    if len(rows) != len(expected):
        problems.append(f"the sheet has {len(rows)} rows but {len(expected)} are expected; run 'make' again if the lexicon changed")
    if problems:
        print(f"NOTHING WAS CHANGED. {len(problems)} problem(s). The first ones:")
        for p in problems[:15]:
            print("  -", p)
        sys.exit(1)
    stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    removed = changed = kept = 0
    for which in ("user", "proposed"):
        if not os.path.exists(FILES[which]):
            continue
        by_key = {k: (d, rep) for (f, _t), (d, rep, k) in decisions.items() if f == which}
        data = load(which)
        shutil.copyfile(FILES[which], os.path.join(SCHEMA, f"lexicon_{which}.before_review_{stamp}.json"))
        for path, lst in iter_lists(data):
            new = []
            for it in lst:
                k = item_key(it)
                if k in by_key:
                    d, rep = by_key[k]
                    if d == "remove":
                        removed += 1; continue
                    if d == "change":
                        changed += 1; new.append(rep); continue
                    kept += 1
                new.append(it)
            lst[:] = new
        json.dump(data, open(FILES[which], "w", encoding="utf-8"), indent=1, ensure_ascii=False)
    print(f"Applied. removed {removed} entries, changed {changed}, kept {kept} (counted per place a term is used).")
    print("Backups: schema\\lexicon_*.before_review_%s.json" % stamp)
    print("NEXT: py scripts\\merge_proposed.py   then   py scripts\\check_lexicon.py   then   py scripts\\evaluate_text.py")

if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in ("make", "apply"):
        sys.exit(__doc__)
    make() if sys.argv[1] == "make" else apply()
