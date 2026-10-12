"""'Other' / free-text path: turns a short message into a SUGGESTED category and subtype. The resident always confirms.
Layers: (1) safety flags from the lexicon, (2) lexicon votes, (3) TF-IDF + logistic regression, (4) agreement rules.
Demo-grade: trained on templates. Must be tested on real messages (see data/real_messages_template.csv)."""
import os, re, json, joblib
import triage_core as t

with open(os.path.join(t.ROOT, "schema", "lexicon.json"), encoding="utf-8") as f:
    LEX = json.load(f)
_UP = os.path.join(t.ROOT, "schema", "lexicon_user.json")
if os.path.exists(_UP):                                        # merge the terms YOU added (Swahili, Sheng, mixed)
    with open(_UP, encoding="utf-8") as f:
        _U = json.load(f)
    for k, terms in _U.get("flags", {}).items():
        LEX["flags"].setdefault(k, []).extend(x.lower().strip() for x in terms if x.strip())
    for c, v in _U.get("categories", {}).items():
        if c in LEX["categories"]:
            LEX["categories"][c]["terms"].extend(x.lower().strip() for x in v.get("terms", []) if x.strip())
            for sub, terms in v.get("subtypes", {}).items():
                LEX["categories"][c].setdefault("subtypes", {}).setdefault(sub, []).extend(x.lower().strip() for x in terms if x.strip())
_CLF_PATH = os.path.join(t.ROOT, "models", "text_classifier.joblib")
CLF = joblib.load(_CLF_PATH) if os.path.exists(_CLF_PATH) else None
FLAG_TARGET = {"self_harm": ("Other / General", "mental_health_crisis", "High"),
               "sexual_violence": ("Security Threat", "sexual_violence", "Medium"),
               "domestic_violence": ("Security Threat", "domestic_violence", "Low")}

def normalize_text(s):
    s = s.lower().replace("’", "'")
    return re.sub(r"\s+", " ", re.sub(r"[^a-z0-9' ]+", " ", s)).strip()

def _hit(term, s):
    return re.search(r"(?<![a-z0-9])" + re.escape(term) + r"(?![a-z0-9])", s) is not None

def lexicon_flags(s):
    return [f for f, terms in LEX["flags"].items() if any(_hit(x, s) for x in terms)]

def lexicon_votes(s):
    """One vote per distinct matched keyword. A keyword inside a longer matched keyword ('fire' inside 'on fire') is not counted twice."""
    votes = {}
    for c, v in LEX["categories"].items():
        hits = {x for x in v["terms"] if _hit(x, s)}
        votes[c] = len([x for x in hits if not any(x != y and x in y for y in hits)])
    return votes

def classifier_probs(s):
    if CLF is None:
        return {}
    P = CLF.predict_proba([s])[0]
    return dict(zip(CLF.classes_, P))

def subtype_for(category, s):
    for sub, terms in LEX["categories"][category].get("subtypes", {}).items():
        if any(_hit(x, s) for x in terms):
            return sub
    return None

def triage_text(text, use_lexicon=True, use_classifier=True):
    s = normalize_text(text)
    flags = lexicon_flags(s) if use_lexicon else []
    for fl in ("self_harm", "sexual_violence", "domestic_violence"):       # safety flags win, in this order
        if fl in flags:
            cat, sub, floor = FLAG_TARGET[fl]
            return {"category": cat, "subtype": sub, "method": "safety_flag", "confidence": "high", "flags": flags, "priority_floor": floor,
                    "needs_clarification": False, "alternatives": [], "requires_confirmation": True}
    votes = lexicon_votes(s) if use_lexicon else {c: 0 for c in t.CATEGORIES}
    top_v = max(votes.values())
    lex_top = [c for c, v in votes.items() if v == top_v and v > 0]
    probs = classifier_probs(s) if use_classifier else {}
    ranked = sorted(probs, key=probs.get, reverse=True)
    clf_top, clf_conf = (ranked[0], probs[ranked[0]]) if ranked else (None, 0.0)
    cat, method, conf = None, "unclear", "low"
    if len(lex_top) == 1:
        lt = lex_top[0]
        if clf_top is None or clf_top == lt:
            cat, method, conf = lt, ("lexicon+classifier" if clf_top else "lexicon"), "high"
        elif clf_conf < 0.5:
            cat, method, conf = lt, "lexicon", "medium"
    elif len(lex_top) > 1:                                              # mixed signals: do not guess, ask the resident
        cat, method, conf = None, "ambiguous", "low"
    elif not lex_top and clf_top and clf_conf >= 0.55:
        cat, method, conf = clf_top, "classifier", "medium"
    alts = [c for c in (sorted(lex_top, key=lambda c: -probs.get(c, 0)) + ranked) if c != cat]
    alts = list(dict.fromkeys(alts))[:2]
    return {"category": cat, "subtype": subtype_for(cat, s) if cat else None, "method": method, "confidence": conf, "flags": flags,
            "priority_floor": "Low", "needs_clarification": cat is None, "alternatives": alts, "requires_confirmation": True}
