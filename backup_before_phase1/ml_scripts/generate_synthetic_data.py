"""Synthetic triage data v3 (NOT real data).
Two parts:
  coverage  = every valid answer combination once (so the model never meets an unseen input)
  realistic = answers sampled the way real calls probably look, with noise
Run from anywhere:  py scripts\\generate_synthetic_data.py
"""
import os, numpy as np, pandas as pd
import triage_core as t

SEED, N_REALISTIC, LABEL_NOISE = 42, 4000, 0.04
CAT_MIX = [.28, .24, .14, .14, .04, .16]          # same order as SCHEMA categories
YNU = ["Yes", "No", "Unknown"]

def P(yes, no, unk):  # probability of Yes / No / Unknown
    return dict(zip(YNU, [yes, no, unk]))

OK = lambda good, bad, unk: P(good, bad, unk)     # for conscious / breathing: Yes means fine
PROFILE = {
 "Medical Emergency": dict(age_group=dict(Adult=.65, Child=.25, Unknown=.10), conscious=OK(.80,.12,.08), breathing=OK(.86,.08,.06),
        severe_bleeding=P(.10,.82,.08), chest_pain=P(.15,.78,.07), pregnant=P(.12,.82,.06), people=[.70,.18,.08,.03,.01]),
 "Road Accident": dict(age_group=dict(Adult=.78, Child=.12, Unknown=.10), conscious=OK(.82,.08,.10), breathing=OK(.90,.04,.06),
        severe_bleeding=P(.15,.78,.07), trapped=P(.25,.62,.13), hazard=P(.10,.80,.10), pregnant=P(.04,.92,.04), people=[.35,.30,.18,.10,.07]),
 "Fire & Rescue": dict(age_group=dict(Adult=.70, Child=.20, Unknown=.10), conscious=OK(.88,.04,.08), breathing=OK(.90,.04,.06),
        trapped=P(.15,.70,.15), hazard=P(.55,.35,.10), people=[.35,.30,.18,.10,.07]),
 "Security Threat": dict(age_group=dict(Adult=.82, Child=.08, Unknown=.10), conscious=OK(.92,.03,.05), breathing=OK(.95,.02,.03),
        severe_bleeding=P(.12,.80,.08), weapon_involved=P(.30,.55,.15), immediate_danger=P(.35,.50,.15), people=[.40,.30,.15,.10,.05]),
 "Abduction": dict(age_group=dict(Adult=.50, Child=.40, Unknown=.10), weapon_involved=P(.40,.45,.15), immediate_danger=P(.30,.50,.20), people=[.55,.25,.10,.06,.04]),
 "Other / General": dict(age_group=dict(Adult=.75, Child=.15, Unknown=.10), conscious=OK(.93,.02,.05), breathing=OK(.95,.02,.03),
        severe_bleeding=P(.05,.90,.05), people=[.70,.18,.08,.03,.01]),
}

def draw(rng, d):
    return rng.choice(list(d), p=list(d.values()))

def make_realistic(rng, cat):
    prof, ans = PROFILE[cat], {"category": cat}
    for q in t.SCHEMA["categories"][cat]["questions"]:
        if q == "people_count":
            ans[q] = int(rng.choice([1, 2, 3, 4, 5], p=prof["people"]))
        elif q == "age_group":
            ans[q] = draw(rng, prof[q])
        elif t._is_asked(q, ans):
            ans[q] = draw(rng, prof[q])
    return t.normalize(ans)

def run_anchors():
    """Clinical sense checks. Generation aborts if any fails."""
    base = dict(category="", age_group="Adult", conscious="Yes", breathing="Yes", severe_bleeding="No", chest_pain="No",
                pregnant="No", trapped="No", hazard="No", weapon_involved="No", immediate_danger="No", people_count=1)
    def chk(exp, **kw):
        n = t.normalize({**base, **kw}); got = t.reference_priority(n)
        assert got == exp, (exp, got, kw)
    chk("High", category="Security Threat", weapon_involved="Yes")
    chk("Medium", category="Security Threat")
    chk("High", category="Security Threat", immediate_danger="Yes")
    for a in ("Adult", "Child", "Unknown"):
        chk("High", category="Abduction", age_group=a)
    chk("High", category="Road Accident", trapped="Yes", conscious="Unknown")
    chk("High", category="Road Accident", trapped="Yes", hazard="Yes")
    chk("Low", category="Road Accident")
    chk("Medium", category="Road Accident", people_count=4)
    chk("High", category="Road Accident", conscious="Unknown", breathing="Unknown")
    chk("High", category="Road Accident", severe_bleeding="Yes")
    chk("Medium", category="Medical Emergency")
    chk("High", category="Medical Emergency", conscious="No")
    chk("High", category="Medical Emergency", breathing="No")
    chk("High", category="Medical Emergency", chest_pain="Yes")
    chk("Medium", category="Medical Emergency", pregnant="Yes")
    chk("High", category="Medical Emergency", pregnant="Yes", conscious="Unknown")
    chk("Medium", category="Fire & Rescue")
    chk("High", category="Fire & Rescue", trapped="Yes")
    chk("Low", category="Other / General")
    chk("High", category="Other / General", conscious="No")
    n = t.normalize({**base, "category": "Security Threat"})
    assert t.reference_priority(n, "sexual_violence") == "Medium"          # floor, never Low
    n = t.normalize({**base, "category": "Other / General"})
    assert t.reference_priority(n, "mental_health_crisis") == "High"
    print("anchors: 23 clinical checks passed")

def build():
    rng = np.random.default_rng(SEED)
    rows = []
    for cat in t.CATEGORIES:                                   # part A: coverage
        for n in t.all_combinations(cat):
            s = t.risk_score(n)
            rows.append({**n, "priority": t.reference_priority(n), "sample_source": "coverage", "risk_score": round(s, 2), "label_was_noised": 0})
    for _ in range(N_REALISTIC):                                # part B: realistic
        cat = t.CATEGORIES[rng.choice(len(t.CATEGORIES), p=CAT_MIX)]
        n = make_realistic(rng, cat)
        s = t.risk_score(n) + rng.normal(0, 0.5)
        lab = t.score_to_label(s)
        floor, _ = t.rule_floor(n)
        if t.RANK[lab] < t.RANK[floor]:
            lab = floor
        noised = 0
        if floor == "Low" and rng.random() < LABEL_NOISE:      # never noise a floored (life-threat) case
            new = {"Low": "Medium", "Medium": "High", "High": "Medium"}[lab] if rng.random() < .7 else {"Low": "Low", "Medium": "Low", "High": "Medium"}[lab]
            if new != lab:
                lab, noised = new, 1
        rows.append({**n, "priority": lab, "sample_source": "realistic", "risk_score": round(s, 2), "label_was_noised": noised})
    return pd.DataFrame(rows)

if __name__ == "__main__":
    run_anchors()
    df = build()
    os.makedirs(os.path.join(t.ROOT, "data"), exist_ok=True)
    df.to_csv(os.path.join(t.ROOT, "data", "synthetic_triage_data.csv"), index=False)
    for src in ("coverage", "realistic"):
        d = df[df.sample_source == src]
        print(f"\n{src}: {len(d)} rows  ", d.priority.value_counts(normalize=True).round(3).to_dict())
    print("\nrealistic rows by category and priority:")
    print(pd.crosstab(df[df.sample_source == "realistic"].category, df[df.sample_source == "realistic"].priority))
    print("noised labels:", int(df.label_was_noised.sum()))
