"""Free-text path: turns a short message into a SUGGESTED category, subtype and safety flags. The resident ALWAYS confirms.

WHY THIS FILE EXISTS
  Words in Swahili, Sheng and English overlap a lot ("moto" = fire or hot, "piga" = hit or call, "basi" = bus or "then").
  A plain keyword list cannot tell these apart, so this version separates meanings with SIX explicit mechanisms.
  Nothing here "guesses": when the evidence is mixed, the result is "ask the resident".

THE SIX MECHANISMS (details in docs/text_triage_architecture.md)
  1. TIERS         strong terms can decide alone; weak terms can only support or ask a question.
  2. OWNERSHIP     one strong term belongs to ONE category (checked by scripts/check_lexicon.py).
  3. LONGEST SPAN  "maji ya moto" (hot water) beats the "moto" (fire) inside it.
  4. PAIRS         two clues near each other: who + act ("mume wangu" + "ananipiga") for domestic violence.
  5. MORPHOLOGY    one verb root covers its Swahili forms (ananipiga, alinipiga, hunipiga, kunipiga ...),
                   and the reflexive "ji-" separates killing yourself (kujiua) from killing someone (kuniua).
  6. IDIOM MASKS   phrases such as "hakuna wasiwasi" (no worries) or "kupiga simu" (to call) are blanked before matching.

Layers: (1) safety flags, (2) lexicon votes, (3) TF-IDF + logistic regression, (4) agreement rules.
Never raises on bad input: the worst case is {"category": None, "needs_clarification": True}.
"""
import os
import re
import sys
import json
import joblib
import triage_core as t

# ----------------------------------------------------------------------------------------------
# Verb morphology (Swahili verbs are built as SUBJECT + TENSE + OBJECT + ROOT, e.g. a-na-ni-piga)
# ----------------------------------------------------------------------------------------------
_SUBJ = r"(?:ni|u|a|tu|m|wa|i|zi|li|ya|ki|vi|ku|pa)"      # who does it (I, you, he/she, we, you-pl, they, things)
_TENSE = r"(?:nge|na|me|li|ta|ka|ki|si)"                        # present, perfect, past, future, narrative ...
_REL = r"(?:ye|yo|o|lo|cho|vyo|zo|ko|po|mo)?"               # relative marker: aliyepotea (who got lost), waliotekwa (who were taken)
_NEG = r"(?:ha|si|hatu|ham|hawa|hai|hazi|hali|haya|haki|havi|haku|hapa)(?:ja|ku|ta|ki)"   # negative: hajarudi (has not returned), hakurudi
_PRE = rf"(?:ku|hu|na|{_SUBJ}{_TENSE}{_REL}|{_NEG})"        # 'na' alone = contracted ni+na ("nataka"); 'hu' = habitual; 'ku' = infinitive
_PRE_1 = rf"(?:na|(?:ni|tu){_TENSE}{_REL})"                 # first person only: nimepotea (I am lost), tumevamiwa (we were attacked)
_PRE_3 = rf"(?:(?:a|wa){_TENSE}{_REL}|{_NEG})"              # he/she/they: amepotea, wametekwa, hajarudi
_PRE_I = rf"(?:(?:i|li|ya|zi|u|ki|vi|pa|ku){_TENSE}{_REL})" # a THING is the subject: imepinduka (it overturned), inaungua (it is burning)
_OBJ_PERSON = r"(?:ni|tu|ku|m|mw|wa)"                       # me, us, you, him/her, them
_OBJ_ME_US = r"(?:ni|tu)"                                   # victim is the speaker (or the speaker's group)
_VERB_KINDS = {                                             # prefix -> object-marker pattern
    "v0": "",                                               # no object marker (also used for passives such as 'pigwa')
    "v": rf"(?:{_OBJ_PERSON})?",                            # optional object marker
    "vo": _OBJ_ME_US,                                       # object marker 'me/us' is required (done TO me)
    "vx": rf"{_OBJ_PERSON}",                                # ANY person object marker is required (done TO someone); blocks 'piga pasi' (iron)
    "vr": "ji",                                             # reflexive marker 'ji' is required (done to oneself)
    "v1": "",                                               # subject must be I/we (nimepotea); no object marker
    "v3": rf"(?:{_OBJ_PERSON})?",                           # subject must be he/she/they (amemchukua); optional object marker
    "vi": rf"(?:{_OBJ_PERSON})?",                           # subject must be a thing (imepinduka, inaungua, imemgonga); optional object marker
}
_KIND_PRE = {"v1": _PRE_1, "v3": _PRE_3, "vi": _PRE_I}      # kinds with their own subject pattern (all others use _PRE)
_KIND_RE = re.compile(r"^(v0|vo|vr|vx|v1|v3|vi|v):(.*)$")
FLAG_ORDER = ("self_harm", "sexual_violence", "domestic_violence")     # safety flags win in this order
FLAG_TARGET = {"self_harm": ("Other / General", "mental_health_crisis", "High"),
               "sexual_violence": ("Security Threat", "sexual_violence", "Medium"),
               "domestic_violence": ("Security Threat", "domestic_violence", "Low")}
MAX_TEXT_CHARS = 2000                                       # longer input is cut (protects speed and memory)

LOAD_WARNINGS = []                                          # problems found while loading lexicon files (shown by evaluate_text / lint)


def _warn(msg):
    """Record a loading problem and print it once to stderr. Loading never stops because of a user-file typo."""
    LOAD_WARNINGS.append(msg)
    print("[text_triage] WARNING:", msg, file=sys.stderr)


def normalize_text(s):
    """Lower-case, keep letters, digits and the apostrophe (kung'atwa), collapse spaces."""
    s = str(s).lower().replace("’", "'")
    return re.sub(r"\s+", " ", re.sub(r"[^a-z0-9' ]+", " ", s)).strip()


def canonical_text(s):
    """Undo how people really type under stress. Applied AFTER normalize_text, for matching only (never shown):
       - a run of 3+ identical letters becomes one ("moooto" -> "moto", "helppp" -> "help"); real words never have 3 in a row
       - SMS short forms of 'ni-' verbs: "nmeibiwa" -> "nimeibiwa", "nlipigwa" -> "nilipigwa", "ntakufa" -> "nitakufa"."""
    s = re.sub(r"(.)\1{2,}", r"\1", s)
    return re.sub(r"\bn([mltk])(?=[aeiou])", r"ni\1", s)


# ----------------------------------------------------------------------------------------------
# Term: one searchable item (plain word/phrase or verb pattern)
# ----------------------------------------------------------------------------------------------
class Term:
    """A compiled lexicon entry. `key` identifies duplicates; `rx` finds it in normalised text."""
    __slots__ = ("raw", "key", "rx", "kind", "plain")

    def __init__(self, raw):
        self.raw = raw
        text = str(raw).strip().lower().replace("’", "'")
        m = _KIND_RE.match(text)
        if m:                                               # verb pattern, e.g. "vr:ua" or "v0:taka kufa"
            self.kind = m.group(1)
            tokens = normalize_text(m.group(2)).split()
            if not tokens or not re.fullmatch(r"[a-z']+", tokens[0]):
                raise ValueError(f"verb pattern needs a root made of letters: {raw!r}")
            body = rf"{_KIND_PRE.get(self.kind, _PRE)}{_VERB_KINDS[self.kind]}{re.escape(tokens[0])}"
            rest = "".join(r"\s+" + re.escape(tok) for tok in tokens[1:])
            self.key = self.kind + ":" + " ".join(tokens)
            self.plain = None
        else:                                               # plain word or phrase
            self.kind = "plain"
            tokens = normalize_text(text).split()
            if not tokens:
                raise ValueError(f"empty term: {raw!r}")
            body = r"\s+".join(re.escape(tok) for tok in tokens)
            rest = ""
            self.key = " ".join(tokens)
            self.plain = self.key
        self.rx = re.compile(r"(?<![a-z0-9'])" + body + rest + r"(?![a-z0-9'])")

    def spans(self, s):
        """All (start, end) places where this term occurs in s."""
        return [(m.start(), m.end()) for m in self.rx.finditer(s)]


class Pair:
    """Two clues that must appear within `window` words of each other ('who' + 'act')."""
    __slots__ = ("who", "act", "window", "label")

    def __init__(self, d):
        self.who = [Term(x) for x in d.get("who", [])]
        self.act = [Term(x) for x in d.get("act", [])]
        self.window = int(d.get("window", 8))
        if not self.who or not self.act:
            raise ValueError("a pair needs at least one 'who' term and one 'act' term")
        self.label = "pair(" + "/".join(x.key for x in self.who[:2]) + " + " + "/".join(x.key for x in self.act[:2]) + ")"

    def find(self, s):
        """Return [(start, end, shown_text)] for every who/act couple that is close enough."""
        found = []
        wh = [(a, b) for x in self.who for a, b in x.spans(s)]
        ac = [(a, b) for x in self.act for a, b in x.spans(s)]
        for (a1, b1) in wh:
            for (a2, b2) in ac:
                if b1 <= a2:
                    gap = s[b1:a2]
                elif b2 <= a1:
                    gap = s[b2:a1]
                else:
                    continue                                # overlapping words are not a couple
                if len(gap.split()) <= self.window:
                    lo, hi = min(a1, a2), max(b1, b2)
                    found.append((lo, hi, s[lo:hi]))
        return found


def _compile_list(items, where):
    """Split a raw list into (terms, pairs). Skips and reports bad entries. Removes exact duplicates."""
    terms, pairs, seen = [], [], set()
    for it in items or []:
        try:
            if isinstance(it, dict) and "pair" in it:
                pairs.append(Pair(it["pair"]))
            elif isinstance(it, str):
                if not it.strip():
                    continue
                tm = Term(it)
                if tm.key not in seen:
                    seen.add(tm.key)
                    terms.append(tm)
            else:
                raise ValueError(f"unknown entry type {type(it).__name__}")
        except (ValueError, re.error) as e:
            _warn(f"{where}: skipped {it!r} ({e})")
    return terms, pairs


# ----------------------------------------------------------------------------------------------
# Loading the lexicon files
# ----------------------------------------------------------------------------------------------
def _read_json(path, required):
    """Read a JSON file. A missing/invalid OPTIONAL file is reported and skipped; the base file must exist."""
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        if required:
            raise RuntimeError(f"required file missing: {path}")
        return None
    except json.JSONDecodeError as e:
        msg = f"{os.path.basename(path)} is not valid JSON (line {e.lineno}, column {e.colno}): {e.msg}. The file was IGNORED."
        if required:
            raise RuntimeError(msg)
        _warn(msg)
        return None


def _tiers(v):
    """A flag entry may be a plain list (= strong terms) or {'strong': [...], 'weak': [...]}."""
    if isinstance(v, list):
        return list(v), []
    if isinstance(v, dict):
        return list(v.get("strong", v.get("terms", []))), list(v.get("weak", v.get("weak_terms", [])))
    return [], []


def merge_raw(base, extra):
    """Combine two raw lexicon dicts (lists are appended; duplicates are removed later by _compile_list)."""
    out = json.loads(json.dumps(base))
    if not extra:
        return out
    for name, v in extra.get("flags", {}).items():
        s, w = _tiers(v)
        cur_s, cur_w = _tiers(out.setdefault("flags", {}).get(name, []))
        out["flags"][name] = {"strong": cur_s + s, "weak": cur_w + w}
    for name, v in out.get("flags", {}).items():                 # normalise untouched flags too
        if isinstance(v, list):
            out["flags"][name] = {"strong": list(v), "weak": []}
    for cat, v in extra.get("categories", {}).items():
        if cat not in out["categories"]:
            _warn(f"unknown category {cat!r} in an extra lexicon file: skipped")
            continue
        c = out["categories"][cat]
        c["terms"] = list(c.get("terms", [])) + list(v.get("terms", []))
        c["weak_terms"] = list(c.get("weak_terms", [])) + list(v.get("weak_terms", []))
        for key in ("subtypes", "subtype_weak"):
            for sub, lst in v.get(key, {}).items():
                c.setdefault(key, {}).setdefault(sub, [])
                c[key][sub] = list(c[key][sub]) + list(lst)
    for key in ("themes",):
        for name, lst in extra.get(key, {}).items():
            out.setdefault(key, {}).setdefault(name, [])
            out[key][name] = list(out[key][name]) + list(lst)
    for key in ("ignore_phrases", "common_words", "tests"):
        out[key] = list(out.get(key, [])) + list(extra.get(key, []))
    return out


def load_raw(include_proposed=None):
    """Raw merged lexicon (base English + the owner's file [+ proposed terms for testing])."""
    base = _read_json(os.path.join(t.ROOT, "schema", "lexicon.json"), required=True)
    raw = merge_raw(base, None)
    raw = merge_raw(raw, _read_json(os.path.join(t.ROOT, "schema", "lexicon_ke.json"), required=False))   # Kenya base: Swahili, Sheng and extra English (assistant-written)
    raw = merge_raw(raw, _read_json(os.path.join(t.ROOT, "schema", "lexicon_user.json"), required=False))  # the owner's own additions
    if include_proposed is None:
        include_proposed = os.environ.get("TRIAGE_INCLUDE_PROPOSED") == "1"
    if include_proposed:
        raw = merge_raw(raw, _read_json(os.path.join(t.ROOT, "schema", "lexicon_proposed.json"), required=False))
    return raw


def compile_lexicon(raw):
    """Turn the raw dict into searchable objects. Applies the 'common word' guard."""
    common = {normalize_text(w) for w in raw.get("common_words", [])}
    lex = {"flags": {}, "cats": {}, "themes": {}, "ignore": [], "common": common}
    for name, v in raw.get("flags", {}).items():
        s, w = _tiers(v)
        st, sp = _compile_list(s, f"flags.{name}.strong")
        wk, wp = _compile_list(w, f"flags.{name}.weak")
        lex["flags"][name] = {"strong": st, "weak": wk, "pairs": sp, "weak_pairs": wp}
    for cat, v in raw.get("categories", {}).items():
        st, sp = _compile_list(v.get("terms", []), f"{cat}.terms")
        wk, wp = _compile_list(v.get("weak_terms", []), f"{cat}.weak_terms")
        demoted = [x for x in st if x.plain and x.plain in common]       # e.g. 'basi' alone is a common word, never strong
        if demoted:
            for x in demoted:
                _warn(f"{cat}: '{x.plain}' is a very common word, so it was treated as WEAK (use a phrase or a pair instead)")
            st = [x for x in st if x not in demoted]
            wk = wk + demoted
        subs = {}
        for sub, lst in v.get("subtypes", {}).items():
            subs[sub] = {"strong": _compile_list(lst, f"{cat}.subtypes.{sub}"), "weak": ([], [])}
        for sub, lst in v.get("subtype_weak", {}).items():
            subs.setdefault(sub, {"strong": ([], []), "weak": ([], [])})["weak"] = _compile_list(lst, f"{cat}.subtype_weak.{sub}")
        lex["cats"][cat] = {"strong": st, "strong_pairs": sp, "weak": wk, "weak_pairs": wp, "subtypes": subs}
    for name, lst in raw.get("themes", {}).items():
        lex["themes"][name], _ = _compile_list(lst, f"themes.{name}")
    lex["ignore"], _ = _compile_list(raw.get("ignore_phrases", []), "ignore_phrases")
    return lex


RAW = load_raw()
LEX = compile_lexicon(RAW)

_CLF_PATH = os.path.join(t.ROOT, "models", "text_classifier.joblib")
try:
    CLF = joblib.load(_CLF_PATH) if os.path.exists(_CLF_PATH) else None
except Exception as _e:                                        # a broken/old model file must not stop the lexicon path
    _warn(f"text classifier could not be loaded ({type(_e).__name__}); using the lexicon only")
    CLF = None


# ----------------------------------------------------------------------------------------------
# Matching
# ----------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------
# Typo tolerance for SAFETY FLAGS only (a mistyped 'suicde' or 'molestd' must still raise the flag)
# ----------------------------------------------------------------------------------------------
def _one_slip(tok, word):
    """True if `tok` is `word` with ONE letter missing or with two neighbouring letters swapped ('suicde', 'sucidie').
    Deliberately NOT substitutions or insertions: those turn too many ordinary words into flag words
    (an external test showed 'raging' -> 'raping' and 'defined' -> 'defiled')."""
    if len(tok) == len(word) - 1:
        return any(word[:i] + word[i + 1:] == tok for i in range(len(word)))
    if len(tok) == len(word) and tok != word:
        d = [i for i in range(len(word)) if tok[i] != word[i]]
        return len(d) == 2 and d[1] == d[0] + 1 and tok[d[0]] == word[d[1]] and tok[d[1]] == word[d[0]]
    return False


SNAP_NEVER = {"defied"}                                         # real words that are one missing letter from a flag word


def _build_snap_vocab():
    """Distinctive single-word STRONG flag terms (6+ letters). Only these are ever 'snapped' to, so ordinary words are never rewritten."""
    vocab = {}
    for name, f in LEX["flags"].items():
        for tm in f["strong"]:
            if tm.plain and " " not in tm.plain and len(tm.plain) >= 7 and tm.plain not in LEX["common"]:
                vocab[tm.plain] = name
    return vocab


def _all_known_tokens():
    known = set(LEX["common"])
    groups = [LEX["ignore"]]
    for f in LEX["flags"].values():
        groups += [f["strong"], f["weak"]]
    for c in LEX["cats"].values():
        groups += [c["strong"], c["weak"]]
    for g in groups:
        for tm in g:
            if tm.plain:
                known.update(tm.plain.split())
    return known


SNAP_VOCAB = _build_snap_vocab()
KNOWN_TOKENS = _all_known_tokens()


def snap_flag_typos(s):
    """Replace a token that is exactly ONE slip (a missing letter or a neighbouring-letter swap) away from exactly ONE flag word (same first letter, 7+ letter flag words, not itself a
    known lexicon word) with that flag word. Used for flag detection only, so it can add a safety flag but never changes a category."""
    out = []
    for tok in s.split():
        if len(tok) >= 6 and tok not in KNOWN_TOKENS and tok not in SNAP_VOCAB and tok not in SNAP_NEVER:
            cands = [v for v in SNAP_VOCAB if v[0] == tok[0] and _one_slip(tok, v)]
            if cands and len({SNAP_VOCAB[c] for c in cands}) == 1:      # unambiguous: every candidate belongs to the same flag
                tok = sorted(cands)[0]
        out.append(tok)
    return " ".join(out)



def _mask_idioms(s):
    """Blank out idioms that would cause false matches ('hakuna wasiwasi' = no worries, 'kupiga simu' = to call)."""
    for tm in LEX["ignore"]:
        for a, b in tm.spans(s):
            s = s[:a] + " " * (b - a) + s[b:]
    return s


def _hits(terms, pairs, s, label, tier):
    """Collect hits (start, end, label, tier, shown_text) for a list of terms and pairs."""
    out = []
    for tm in terms:
        for a, b in tm.spans(s):
            out.append((a, b, label, tier, tm.key))
    for p in pairs:
        for a, b, shown in p.find(s):
            out.append((a, b, label, tier, p.label))
    return out


def _drop_inside_longer(hits):
    """Longest span wins. A hit strictly inside a longer hit is dropped when the longer one belongs to ANOTHER label
    ('maji ya moto' removes 'moto'); inside the SAME label it is simply not counted twice ('on fire' removes 'fire')."""
    keep = []
    for h in hits:
        inside = any(o is not h and o[0] <= h[0] and o[1] >= h[1] and (o[1] - o[0]) > (h[1] - h[0]) for o in hits)
        if not inside:
            keep.append(h)
    uniq, seen = [], set()
    for h in keep:                                              # same words found twice (strong + pair) count once per label/tier
        k = (h[0], h[1], h[2], h[3])
        if k not in seen:
            seen.add(k)
            uniq.append(h)
    return uniq


def lexicon_flags(s):
    """Return (flags, possible_flags, matched). Strong terms or satisfied pairs -> flag. Weak only -> possible flag."""
    flags, possible, matched = [], [], []
    for name in FLAG_ORDER + tuple(k for k in LEX["flags"] if k not in FLAG_ORDER):
        f = LEX["flags"].get(name)
        if not f:
            continue
        strong = _hits(f["strong"], f["pairs"], s, name, "strong")
        weak = _hits(f["weak"], f["weak_pairs"], s, name, "weak")
        if strong:
            flags.append(name)
            matched += [{"label": "flag:" + h[2], "term": h[4], "tier": "strong"} for h in strong[:3]]
        elif weak:
            possible.append(name)
            matched += [{"label": "possible_flag:" + h[2], "term": h[4], "tier": "weak"} for h in weak[:3]]
    return flags, possible, matched


def lexicon_votes(s):
    """Return (strong_votes {cat: n}, weak_hits {cat: n}, matched). Hits inside a longer hit of another category are dropped first."""
    all_hits = []
    for c, v in LEX["cats"].items():
        all_hits += _hits(v["strong"], v["strong_pairs"], s, c, "strong")
        all_hits += _hits(v["weak"], v["weak_pairs"], s, c, "weak")
    kept = _drop_inside_longer(all_hits)
    strong = {c: 0 for c in LEX["cats"]}
    weak = {}                                                   # category -> number of weak hits (ranks the suggestion chips)
    matched = []
    for h in kept:
        if h[3] == "strong":
            strong[h[2]] += 1
        else:
            weak[h[2]] = weak.get(h[2], 0) + 1
        matched.append({"label": h[2], "term": h[4], "tier": h[3]})
    if strong.get("Medical Emergency", 0) and any(strong.get(c, 0) for c in INCIDENT_CATEGORIES):
        weak["Medical Emergency"] = weak.get("Medical Emergency", 0) + strong["Medical Emergency"]     # still shown as a chip
        strong["Medical Emergency"] = 0
    if strong.get("Other / General", 0) and any(strong.get(c, 0) for c in LEX["cats"] if c != "Other / General"):
        weak["Other / General"] = weak.get("Other / General", 0) + strong["Other / General"]             # 'Other' is the fallback: any specific category wins
        strong["Other / General"] = 0
    return strong, weak, matched


def classifier_probs(s):
    """Probabilities from the TF-IDF + logistic regression model ({} if no model is available)."""
    if CLF is None:
        return {}
    try:
        P = CLF.predict_proba([s])[0]
        return dict(zip(CLF.classes_, P))
    except Exception as e:                                      # never let a model problem break triage
        _warn(f"classifier failed on one message ({type(e).__name__}); lexicon only")
        return {}


def subtype_for(category, s):
    """Pick a subtype from strong terms (most hits wins, a tie returns None so the resident chooses).
    If there is no strong evidence but exactly one subtype has weak evidence, suggest it with LOW confidence."""
    subs = LEX["cats"][category]["subtypes"]
    scores = {}
    for sub, v in subs.items():
        terms, pairs = v["strong"]
        hits = _drop_inside_longer(_hits(terms, pairs, s, sub, "strong"))
        if hits:
            scores[sub] = len(hits)
    if scores:
        top = max(scores.values())
        best = [k for k, n in scores.items() if n == top]
        return (best[0], "high") if len(best) == 1 else (None, "low")
    weak_scores = {}
    for sub, v in subs.items():
        terms, pairs = v["weak"]
        if _hits(terms, pairs, s, sub, "weak"):
            weak_scores[sub] = 1
    if len(weak_scores) == 1:
        return next(iter(weak_scores)), "low"
    return None, "low"


def themes_for(s):
    """Context labels for emotional distress (relationship, exams, money ...). They never vote; they only describe."""
    return [name for name, terms in LEX["themes"].items() if any(tm.spans(s) for tm in terms)]


def _empty_result(**kw):
    """The safe default answer: no decision, ask the resident."""
    r = {"category": None, "subtype": None, "subtype_confidence": "low", "method": "unclear", "confidence": "low", "flags": [],
         "possible_flags": [], "priority_floor": "Low", "needs_clarification": True, "alternatives": [],
         "requires_confirmation": True, "safety_check": False, "themes": [], "matched": []}
    r.update(kw)
    return r


USE_CLASSIFIER_DEFAULT = os.environ.get("TRIAGE_USE_CLASSIFIER") == "1"
# The TF-IDF classifier is OFF by default. Measured on data/text_eval_sw.csv it was WRONG on 11% of Swahili/Sheng messages
# (it was trained mostly on English and guesses "Medical" for almost any Swahili sentence); the lexicon alone was wrong on 0%.
# The phone and the server therefore run the SAME rule engine, so they can never disagree. TRIAGE_USE_CLASSIFIER=1 re-enables it for experiments.
INCIDENT_CATEGORIES = ("Road Accident", "Fire & Rescue", "Security Threat", "Abduction")
MAX_CHIPS = 3                                                   # suggestion chips shown besides the main suggestion


def triage_text(text, use_lexicon=True, use_classifier=None):
    """Suggest category/subtype/flags for one message. Never raises; the resident always confirms."""
    if use_classifier is None:
        use_classifier = USE_CLASSIFIER_DEFAULT
    try:
        if not isinstance(text, str) or not text.strip():
            return _empty_result(method="empty")
        s = _mask_idioms(canonical_text(normalize_text(text[:MAX_TEXT_CHARS])))
        flags, possible, fmatched = lexicon_flags(snap_flag_typos(s)) if use_lexicon else ([], [], [])
        for fl in FLAG_ORDER:                                    # safety flags win, in this order
            if fl in flags:
                cat, sub, floor = FLAG_TARGET[fl]
                return _empty_result(category=cat, subtype=sub, subtype_confidence="high", method="safety_flag", confidence="high",
                                     flags=flags, possible_flags=possible, priority_floor=floor, needs_clarification=False,
                                     safety_check=True, matched=fmatched)
        if use_lexicon:
            strong, weak_cats, cmatched = lexicon_votes(s)
        else:
            strong, weak_cats, cmatched = {c: 0 for c in t.CATEGORIES}, {}, []
        top_v = max(strong.values()) if strong else 0
        lex_top = [c for c, v in strong.items() if v == top_v and v > 0]
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
        elif len(lex_top) > 1:                                   # mixed strong signals: do not guess, ask the resident
            cat, method, conf = None, "ambiguous", "low"
        elif len(weak_cats) == 1 and clf_top in weak_cats and clf_conf >= 0.55:
            cat, method, conf = clf_top, "lexicon_weak+classifier", "medium"
        elif not weak_cats and clf_top and clf_conf >= 0.55:
            cat, method, conf = clf_top, "classifier", "medium"
        order = {c: i for i, c in enumerate(LEX["cats"])}
        evidence = [c for c in LEX["cats"] if strong.get(c, 0) > 0 or weak_cats.get(c, 0) > 0]
        evidence.sort(key=lambda c: (-strong.get(c, 0), -weak_cats.get(c, 0), -probs.get(c, 0.0), order[c]))
        alts = [c for c in evidence if c != cat]
        alts += [c for c in ranked if c != cat and c not in alts]                    # classifier chips only if it is switched on
        alts = alts[:MAX_CHIPS]
        sub, sub_conf = subtype_for(cat, s) if cat else (None, "low")
        # A weak flag is only worth a question when we do not already understand the message.
        # Exception: a possible self-harm signal is ALWAYS kept (cost of missing it is too high).
        possible = [f for f in possible if f == "self_harm" or cat is None]
        themes = themes_for(s) if sub == "emotional_distress" else []
        return _empty_result(category=cat, subtype=sub, subtype_confidence=sub_conf, method=method, confidence=conf, flags=flags,
                             possible_flags=possible, needs_clarification=cat is None, alternatives=alts,
                             safety_check=(sub == "emotional_distress" or "self_harm" in possible), themes=themes,
                             matched=(fmatched + cmatched)[:8])
    except Exception as e:                                       # last line of defence: never crash the app path
        return _empty_result(method="error", error=f"{type(e).__name__}: {e}")
