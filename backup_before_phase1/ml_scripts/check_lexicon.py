"""Lexicon checker (lint). Run after EVERY edit of schema/lexicon_user.json:   py scripts\\check_lexicon.py
Add --proposed to check what would happen if schema/lexicon_proposed.json were merged.

It finds the mistakes that cause wrong classification:
  ERROR  a term that cannot be read, the same STRONG term owned by two categories, a built-in test that fails
  WARN   duplicates inside one list, text that normalisation would change (capitals, punctuation),
         a term that is both strong and weak, one term in two subtypes (the subtype becomes 'ask the resident')
  INFO   redundant phrases (already covered by a shorter strong term in the same category)
Exit code 1 when there is at least one ERROR (so it can be used before every commit)."""
import sys
import os
import json
import collections
import triage_core as t
import text_triage as T

USE_PROPOSED = "--proposed" in sys.argv
issues = {"ERROR": [], "WARN": [], "INFO": []}


def say(level, msg):
    issues[level].append(msg)
    print(f"{level:5s} {msg}")


def raw_lists(d, fname):
    """Yield (section, tier, [entries]) for one raw lexicon file."""
    for name, v in d.get("flags", {}).items():
        s, w = T._tiers(v)
        yield f"{fname}: flags.{name}", "strong", s
        yield f"{fname}: flags.{name}", "weak", w
    for cat, v in d.get("categories", {}).items():
        yield f"{fname}: {cat}", "strong", v.get("terms", [])
        yield f"{fname}: {cat}", "weak", v.get("weak_terms", [])
        for sub, lst in v.get("subtypes", {}).items():
            yield f"{fname}: {cat}/{sub}", "subtype", lst
        for sub, lst in v.get("subtype_weak", {}).items():
            yield f"{fname}: {cat}/{sub}", "subtype-weak", lst
    for th, lst in d.get("themes", {}).items():
        yield f"{fname}: themes.{th}", "context", lst
    yield f"{fname}: ignore_phrases", "mask", d.get("ignore_phrases", [])


def check_file(fname):
    path = os.path.join(t.ROOT, "schema", fname)
    if not os.path.exists(path):
        return
    try:
        d = json.load(open(path, encoding="utf-8"))
    except json.JSONDecodeError as e:
        say("ERROR", f"{fname}: not valid JSON (line {e.lineno}, column {e.colno}): {e.msg}")
        return
    for section, tier, items in raw_lists(d, fname):
        seen = collections.Counter()
        for it in items:
            if isinstance(it, dict):
                try:
                    T.Pair(it["pair"])
                except Exception as e:
                    say("ERROR", f"{section} [{tier}]: bad pair {json.dumps(it, ensure_ascii=False)[:80]} ({e})")
                continue
            if not isinstance(it, str):
                say("ERROR", f"{section} [{tier}]: entry {it!r} is not text")
                continue
            try:
                tm = T.Term(it)
            except Exception as e:
                say("ERROR", f"{section} [{tier}]: {it!r} cannot be used ({e})")
                continue
            seen[tm.key] += 1
            if tm.kind == "plain" and T.normalize_text(it) != it.strip():
                say("WARN", f"{section} [{tier}]: {it!r} will be read as {T.normalize_text(it)!r} (use lowercase, no punctuation except ')")
        for k, n in seen.items():
            if n > 1:
                say("WARN", f"{section} [{tier}]: {k!r} appears {n} times (duplicates are ignored, please delete them)")


raw = T.load_raw(include_proposed=USE_PROPOSED)
lex = T.compile_lexicon(raw)
T.RAW, T.LEX = raw, lex                                      # so the built-in tests below use the same lexicon
for fn in ("lexicon.json", "lexicon_user.json") + (("lexicon_proposed.json",) if USE_PROPOSED else ()):
    check_file(fn)
for w in T.LOAD_WARNINGS:
    say("WARN", "loader: " + w)

# --- ownership: a STRONG term may decide only ONE category ---------------------------------------------------------
owner = collections.defaultdict(set)
for c, v in lex["cats"].items():
    for tm in v["strong"]:
        owner[tm.key].add(c)
for key, cats in sorted(owner.items()):
    if len(cats) > 1:
        say("ERROR", f"strong term {key!r} is owned by {sorted(cats)}: it will cause 'ambiguous'. Keep it strong in ONE category, make it weak elsewhere")
for c, v in lex["cats"].items():
    strong_keys = {x.key for x in v["strong"]}
    for x in v["weak"]:
        if x.key in strong_keys:
            say("WARN", f"{c}: {x.key!r} is both strong and weak")
    plain = sorted((x.plain for x in v["strong"] if x.plain), key=len)
    for i, a in enumerate(plain):                              # redundant phrase: contains a shorter strong term
        for b in plain[i + 1:]:
            if a != b and (f" {a} " in f" {b} "):
                say("INFO", f"{c}: {b!r} is already covered by the shorter strong term {a!r}")
    sub_owner = collections.defaultdict(set)
    for sub, sv in v["subtypes"].items():
        for tm in sv["strong"][0]:
            sub_owner[tm.key].add(sub)
    for key, subs in sub_owner.items():
        if len(subs) > 1:
            say("WARN", f"{c}: {key!r} is a strong term in several subtypes {sorted(subs)}: the subtype will not be chosen automatically")
all_strong_flag = collections.defaultdict(set)
for name, f in lex["flags"].items():
    for tm in f["strong"]:
        all_strong_flag[tm.key].add(name)
for key, names in all_strong_flag.items():
    if len(names) > 1:
        say("ERROR", f"flag term {key!r} is strong in {sorted(names)}: only the first flag would ever fire")

# --- built-in tests (lexicon only: the classifier knows no Swahili) --------------------------------------------------
passed = failed = 0
for c in raw.get("tests", []):
    r = T.triage_text(c["text"], use_classifier=False)
    problems = []
    if "category" in c and r["category"] != c["category"]:
        problems.append(f"category {r['category']!r} (wanted {c['category']!r})")
    if "subtype" in c and r["subtype"] != c["subtype"]:
        problems.append(f"subtype {r['subtype']!r} (wanted {c['subtype']!r})")
    if c.get("flag") and c["flag"] not in r["flags"]:
        problems.append(f"flag {c['flag']} not raised (got {r['flags']})")
    if c.get("no_flag") and r["flags"]:
        problems.append(f"unexpected flag {r['flags']}")
    if problems:
        failed += 1
        say("ERROR", f"test {c['text']!r}: " + "; ".join(problems))
    else:
        passed += 1

# --- summary ---------------------------------------------------------------------------------------------------------
n_terms = sum(len(v["strong"]) + len(v["weak"]) for v in lex["cats"].values())
print(f"\nChecked {n_terms} category terms, {sum(len(f['strong']) + len(f['weak']) for f in lex['flags'].values())} flag terms, "
      f"{len(lex['ignore'])} idiom masks. Built-in tests: {passed} passed, {failed} failed.")
print(f"{len(issues['ERROR'])} errors, {len(issues['WARN'])} warnings, {len(issues['INFO'])} notes.")
sys.exit(1 if issues["ERROR"] else 0)
