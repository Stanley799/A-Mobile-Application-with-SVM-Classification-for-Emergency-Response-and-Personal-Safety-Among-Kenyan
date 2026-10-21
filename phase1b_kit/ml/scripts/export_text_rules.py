r"""Exports the compiled text-triage rules for the phone:  py scripts\export_text_rules.py
Writes dart/text_triage_rules.json (copied into the app as assets/text_triage_rules.json) and dart/text_triage_vectors.json (test vectors).
The phone loads the rules file and runs the SAME algorithm as scripts/text_triage.py, so a message gets the same answer on the phone and on the server.
Run it again after ANY change to schema/lexicon*.json or scripts/text_triage.py, then re-copy both files into the app."""
import os, sys, json, csv, glob, hashlib
import triage_core as t
import text_triage as T

def term(tm):  return {"k": tm.key, "r": tm.rx.pattern}
def terms(lst): return [term(x) for x in lst]
def pairs(lst): return [{"who": terms(p.who), "act": terms(p.act), "w": p.window, "l": p.label} for p in lst]

rules = {
  "version": 1,
  "constants": {"flagOrder": list(T.FLAG_ORDER), "flagTarget": {k: list(v) for k, v in T.FLAG_TARGET.items()},
                "maxChips": T.MAX_CHIPS, "maxTextChars": T.MAX_TEXT_CHARS, "incident": list(T.INCIDENT_CATEGORIES), "snapNever": sorted(T.SNAP_NEVER)},
  "categoryOrder": list(T.LEX["cats"].keys()),
  "ignore": terms(T.LEX["ignore"]),
  "common": sorted(T.LEX["common"]),
  "snapVocab": T.SNAP_VOCAB,                    # distinctive flag word -> flag name (typo snapping)
  "knownTokens": sorted(T.KNOWN_TOKENS),
  "flags": {name: {"strong": terms(f["strong"]), "weak": terms(f["weak"]), "pairs": pairs(f["pairs"]), "weakPairs": pairs(f["weak_pairs"])} for name, f in T.LEX["flags"].items()},
  "categories": {},
  "themes": {name: terms(lst) for name, lst in T.LEX["themes"].items()},
}
for cat, v in T.LEX["cats"].items():
    subs = {}
    for sub, d in v["subtypes"].items():
        (st, sp), (wt, wp) = d["strong"], d["weak"]
        subs[sub] = {"strong": terms(st), "strongPairs": pairs(sp), "weak": terms(wt), "weakPairs": pairs(wp)}
    rules["categories"][cat] = {"strong": terms(v["strong"]), "strongPairs": pairs(v["strong_pairs"]), "weak": terms(v["weak"]), "weakPairs": pairs(v["weak_pairs"]), "subtypes": subs}

out_dir = os.path.join(t.ROOT, "dart"); os.makedirs(out_dir, exist_ok=True)
with open(os.path.join(out_dir, "text_triage_rules.json"), "w", encoding="utf-8") as f:
    json.dump(rules, f, ensure_ascii=False, separators=(",", ":"))

# ---- test vectors: every labelled message we have + a deterministic sample of synthetic mixtures ----------------------------
msgs = []
for path in sorted(glob.glob(os.path.join(t.ROOT, "data", "text_*.csv"))):
    if os.path.basename(path) in ("text_training_user.csv",): continue
    try:
        for r in csv.DictReader(open(path, encoding="utf-8")):
            if r.get("text"): msgs.append(r["text"])
    except Exception: pass
import random
rnd = random.Random(20261021)
pool = []
for cat in rules["categories"].values():
    for tm in cat["strong"] + cat["weak"]:
        if ":" not in tm["k"]: pool.append(tm["k"])
for f in rules["flags"].values():
    for tm in f["strong"] + f["weak"]:
        if ":" not in tm["k"]: pool.append(tm["k"])
glue = ["na", "ya", "kwa", "tafadhali", "please", "help", "sasa hivi", "my", "mtoto", "wangu", "kuna", "the", "is", "ana", "ako", "nimeona", "jana", "leo", "haraka", "NOW!!", "pls", "plz"]
for _ in range(1500):
    n = rnd.randint(1, 4)
    parts = [rnd.choice(pool) for _ in range(n)] + [rnd.choice(glue) for _ in range(rnd.randint(0, 3))]
    rnd.shuffle(parts)
    msgs.append(" ".join(parts))
for base in ["moooto", "nmeibiwa simu", "NIMEPOTEA NJIA", "  ", "", "😀🔥", "moto!!!", "nimebakwa", "NATAKA KUJIUA", "mke wangu amenajisiwa", "nimekufa njaa", "sucidal", "molestd"]:
    msgs.append(base)
seen, vec = set(), []
for m in msgs:
    if m in seen: continue
    seen.add(m)
    r = T.triage_text(m)
    vec.append({"text": m, "category": r["category"], "subtype": r["subtype"], "subtypeConfidence": r["subtype_confidence"], "method": r["method"], "confidence": r["confidence"],
                "flags": r["flags"], "possibleFlags": r["possible_flags"], "priorityFloor": r["priority_floor"], "needsClarification": r["needs_clarification"],
                "alternatives": r["alternatives"], "safetyCheck": r["safety_check"], "themes": r["themes"]})
with open(os.path.join(out_dir, "text_triage_vectors.json"), "w", encoding="utf-8") as f:
    json.dump(vec, f, ensure_ascii=False, separators=(",", ":"))
for n in ("text_triage_rules.json", "text_triage_vectors.json"):
    p = os.path.join(out_dir, n); b = open(p, "rb").read()
    print(f"{n}: {len(b):,} bytes  sha256={hashlib.sha256(b).hexdigest()[:16]}")
print(len(vec), "test vectors")
