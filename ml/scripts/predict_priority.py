"""Hybrid priority suggestion = rule floors + classifier with a safety bias.  Import suggest_priority() or run this file for examples."""
import os, json, joblib, numpy as np, pandas as pd
import triage_core as t

_MODEL = joblib.load(os.path.join(t.ROOT, "models", "priority_classifier.joblib"))
_META = json.load(open(os.path.join(t.ROOT, "models", "metadata.json")))
_TABLE = json.load(open(os.path.join(t.ROOT, "models", "decision_table.json")))
assert _TABLE["schema_version"] == t.SCHEMA["version"], "Decision table is out of date. Run build_decision_table.py."
assert _META["feature_order"] == t.FEATURES, "Model was trained on a different feature list. Retrain."
assert _META["schema_version"] == t.SCHEMA["version"], "Schema changed since training. Retrain."

def suggest_priority(payload, subtype=None):
    """Looks the answers up in the compiled decision table (model + rule floors + monotone repair), then applies
    subtype floors (sexual violence, mental health) that depend on the subtype the resident chose."""
    n = t.normalize(payload)                                   # strict validation: bad values raise ValueError
    floor, reasons = t.rule_floor(n, subtype)
    e = _TABLE["entries"]["|".join(str(n[f]) for f in t.FEATURES)]
    final = e["p"] if t.RANK[e["p"]] >= t.RANK[floor] else floor
    return {"priority": final, "priority_source": "rule_floor" if t.RANK[floor] > t.RANK[e["p"]] else "model_table",
            "rule_floor": floor, "rule_reasons": reasons, "model_confidence": e["c"],
            "needs_human_review": bool(e["r"]) and floor != "High" and final != "High"}

def suggest_priority_raw_model(payload, subtype=None):
    """Same idea but straight from the trained model (used only to test the table)."""
    n = t.normalize(payload)
    floor, reasons = t.rule_floor(n, subtype)
    X = pd.DataFrame([[n[f] for f in t.FEATURES]], columns=t.FEATURES)
    P = _MODEL.predict_proba(X)[0]; cl = list(_MODEL.classes_)
    model_label = cl[int(P.argmax())]
    if P[cl.index("High")] >= t.SCHEMA["high_threshold"]:      # safety bias
        model_label = "High"
    final = model_label if t.RANK[model_label] >= t.RANK[floor] else floor
    source = "rule_floor" if t.RANK[floor] > t.RANK[model_label] else "model"
    confidence = float(P.max())
    review = (floor != "High") and (confidence < t.CONFIDENCE_FLOOR)
    return {"priority": final, "priority_source": source, "rule_floor": floor, "rule_reasons": reasons,
            "model_label": model_label, "model_confidence": round(confidence, 3),
            "needs_human_review": bool(review), "probabilities": {c: round(float(p), 3) for c, p in zip(cl, P)}}

if __name__ == "__main__":
    base = dict(age_group="Adult", conscious="Yes", breathing="Yes", severe_bleeding="No", chest_pain="No", pregnant="No",
                trapped="No", hazard="No", weapon_involved="No", immediate_danger="No", people_count=1)
    tests = [("Road crash, person trapped, fuel leaking", dict(category="Road Accident", trapped="Yes", hazard="Yes", people_count=2)),
             ("Road crash, minor, walking", dict(category="Road Accident")),
             ("Medical, pregnant, bleeding", dict(category="Medical Emergency", pregnant="Yes", severe_bleeding="Yes")),
             ("Medical, child, all fine", dict(category="Medical Emergency", age_group="Child")),
             ("Security, attacker nearby, no weapon seen", dict(category="Security Threat", immediate_danger="Yes")),
             ("Security, looting seen from afar", dict(category="Security Threat", immediate_danger="No")),
             ("Abduction", dict(category="Abduction")),
             ("Other, nothing wrong", dict(category="Other / General"))]
    for name, kw in tests:
        r = suggest_priority({**base, **kw})
        print(f"{name:45s} -> {r['priority']:6s} (source {r['priority_source']}, confidence {r['model_confidence']}, review={r['needs_human_review']})")
    r = suggest_priority({**base, "category": "Security Threat"}, subtype="sexual_violence")
    print(f"{'Sexual violence, no other danger signs':45s} -> {r['priority']:6s} (floor {r['rule_floor']}: {r['rule_reasons']})")
    try:
        suggest_priority({**base, "category": "Fire and Rescue"})
    except ValueError as e:
        print("typo rejected:", e)
