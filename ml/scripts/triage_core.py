"""Shared rules for the whole project. Everything is read from schema/triage_schema.json.
Used by: data generator, trainer, predictor, tests, responder matching, Dart generator."""
import json, os

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
with open(os.path.join(ROOT, "schema", "triage_schema.json"), encoding="utf-8") as _f:
    SCHEMA = json.load(_f)

NOT_ASKED = SCHEMA["not_asked"]
PRIORITIES = SCHEMA["priorities"]
RANK = {p: i for i, p in enumerate(PRIORITIES)}
CATEGORIES = list(SCHEMA["categories"])
QUESTIONS = SCHEMA["questions"]
FEATURES = SCHEMA["model_features"]
NUMERIC = [f for f in FEATURES if f != "category" and QUESTIONS[f]["type"] == "int"]
CATEGORICAL = [f for f in FEATURES if f not in NUMERIC]
CONFIDENCE_FLOOR = SCHEMA["confidence_floor"]


def allowed_values():
    """Allowed values per categorical feature, including NotAsked."""
    out = {"category": list(CATEGORIES)}
    for f in CATEGORICAL:
        if f != "category":
            out[f] = QUESTIONS[f]["values"] + [NOT_ASKED]
    return out


def _is_asked(question, answers):
    cond = QUESTIONS[question].get("ask_if")
    if not cond:
        return True
    return all(answers.get(k) in v for k, v in cond.items())


def normalize(payload):
    """Validate the resident's answers and return a full feature dict.
    Questions not asked for this category become NotAsked. Wrong values raise ValueError."""
    cat = payload.get("category")
    if cat not in SCHEMA["categories"]:
        raise ValueError(f"Invalid category: {cat!r}")
    out = {f: NOT_ASKED for f in FEATURES if f not in ("category",) + tuple(NUMERIC)}
    out["category"] = cat
    for q in SCHEMA["categories"][cat]["questions"]:
        if not _is_asked(q, out):
            continue
        v = payload.get(q)
        spec = QUESTIONS[q]
        if spec["type"] == "int":
            if isinstance(v, bool) or not isinstance(v, (int, float)) or int(v) != v:
                raise ValueError(f"Invalid {q}: {v!r}")
            out[q] = max(spec["min"], min(spec["max"], int(v)))
        else:
            if v not in spec["values"]:
                raise ValueError(f"Invalid {q}: {v!r}")
            out[q] = v
    for q in NUMERIC:
        out.setdefault(q, 1)
    return out


def asked_for(category, answers=None):
    """List of questions the app should show, in order. Pass answers so conditional questions resolve."""
    answers = answers or {}
    return [q for q in SCHEMA["categories"][category]["questions"] if _is_asked(q, answers)]


def all_combinations(category):
    """Every possible set of answers for a category (the input space is finite)."""
    qs = SCHEMA["categories"][category]["questions"]

    def rec(i, cur):
        if i == len(qs):
            yield dict(cur)
            return
        q = qs[i]
        if not _is_asked(q, cur):
            yield from rec(i + 1, cur)
            return
        spec = QUESTIONS[q]
        vals = list(range(spec["min"], spec["max"] + 1)) if spec["type"] == "int" else spec["values"]
        for v in vals:
            cur[q] = v
            yield from rec(i + 1, cur)
        cur.pop(q, None)

    for combo in rec(0, {}):
        yield normalize({"category": category, **combo})


def risk_score(n):
    w = SCHEMA["weights"]
    s = w["baseline"][n["category"]]["value"]
    for q, table in w["answers"].items():
        s += table.get(n.get(q), {}).get("value", 0)
    s += w["people_count"].get(str(n["people_count"]), {}).get("value", 0)
    return s


def score_to_label(s):
    t = SCHEMA["weights"]["thresholds"]
    return "High" if s >= t["High_at"] else "Medium" if s >= t["Medium_at"] else "Low"


def _cond_true(rule, n, subtype):
    if "category" in rule and rule["category"] != n["category"]:
        return False
    if "subtype" in rule and rule["subtype"] != subtype:
        return False
    conds = rule.get("when", [])
    if not conds:
        return True
    hits = [n.get(c["q"]) in c["in"] for c in conds]
    return any(hits) if rule.get("match", "any") == "any" else all(hits)


def rule_floor(n, subtype=None):
    """Lowest priority the system will allow. Returns (priority, [reasons])."""
    best, reasons = "Low", []
    for r in SCHEMA["floors"]:
        if _cond_true(r, n, subtype):
            reasons.append(r["reason"])
            if RANK[r["floor"]] > RANK[best]:
                best = r["floor"]
    return best, reasons


def reference_priority(n, subtype=None):
    """What the protocol says the answer should be: score label, never below the floor."""
    lab = score_to_label(risk_score(n))
    fl, _ = rule_floor(n, subtype)
    return lab if RANK[lab] >= RANK[fl] else fl


def required_capabilities(n, subtype=None):
    base = SCHEMA["routing"]["base"][n["category"]]
    req, pref = list(base["required"]), list(base["preferred"])
    for r in SCHEMA["routing"]["conditional"]:
        if not _cond_true(r, n, subtype):
            continue
        if "set_required" in r:
            req = list(r["set_required"])
        if "set_preferred" in r:                          # e.g. emotional distress: no ambulance by default
            pref = list(r["set_preferred"])
        for c in r.get("add_required", []):
            if c not in req:
                req.append(c)
        for c in r.get("add_preferred", []):
            if c not in pref:
                pref.append(c)
    pref = [c for c in pref if c not in req]
    return req, pref


def briefing_flags(n):
    labels = SCHEMA["briefing"]["flag_labels"]
    return [labels[q][n[q]] for q in labels if n.get(q) in labels[q]]
