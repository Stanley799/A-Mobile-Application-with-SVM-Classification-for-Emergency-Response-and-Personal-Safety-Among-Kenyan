"""Synthetic triage data v2 (NOT real data). Features == exactly what the app asks.
Labels come from an expert-judgement risk score + noise. Weights are placeholders for clinician review."""
import numpy as np, pandas as pd, sys
SEED = 42
CATS = ["Medical Emergency","Road Accident","Fire & Rescue","Security Threat","Abduction","Other / General"]
BASELINE = {"Medical Emergency":2.0,"Road Accident":0.3,"Fire & Rescue":2.0,"Security Threat":2.0,"Abduction":4.0,"Other / General":0.5}
HIGH_AT, MEDIUM_AT = 4.0, 2.0
ASKED = {  # which category-specific questions the app asks
 "severe_bleeding":{"Medical Emergency","Road Accident"},
 "chest_pain":{"Medical Emergency"},
 "mobile":{"Road Accident","Fire & Rescue"},
 "weapon_involved":{"Security Threat","Abduction"}}
def risk_score(r):
    s = BASELINE[r["category"]]
    for f in ("conscious","breathing"):
        s += {"No":4.0,"Unknown":1.9}.get(r[f],0)
    for f in ("severe_bleeding","chest_pain"):
        s += {"Yes":3.8,"Unknown":0.8}.get(r[f],0)
    s += 3.8*int(r["weapon_involved"])
    s += {"Trapped":2.0,"Unknown":0.5}.get(r["mobile"],0)
    n = int(r["people_count"]); s += 2.2 if n>=4 else 1.7 if n==3 else 0
    return s
def protected(r):
    return (r["conscious"]=="No" or r["breathing"]=="No" or r["severe_bleeding"]=="Yes"
            or r["chest_pain"]=="Yes" or int(r["weapon_involved"])==1 or r["category"]=="Abduction")
def to_label(s): return "High" if s>=HIGH_AT else "Medium" if s>=MEDIUM_AT else "Low"
def row(r_):
    pass
def make_row(rng, cat):
    p = {"Medical Emergency":dict(c=[.80,.12,.08],b=[.86,.08,.06],bl=[.12,.80,.08],cp=[.15,.78,.07],pc=[.70,.18,.08,.03,.01]),
         "Road Accident":    dict(c=[.82,.08,.10],b=[.90,.04,.06],bl=[.15,.78,.07],mo=[.25,.62,.13],pc=[.35,.30,.18,.10,.07]),
         "Fire & Rescue":    dict(c=[.88,.04,.08],b=[.90,.04,.06],mo=[.15,.70,.15],pc=[.35,.30,.18,.10,.07]),
         "Security Threat":  dict(c=[.92,.03,.05],b=[.95,.02,.03],w=.35,pc=[.40,.30,.15,.10,.05]),
         "Abduction":        dict(c=[.88,.04,.08],b=[.92,.03,.05],w=.40,pc=[.55,.25,.10,.06,.04]),
         "Other / General":  dict(c=[.93,.02,.05],b=[.95,.02,.03],pc=[.70,.18,.08,.03,.01])}[cat]
    YNU=["Yes","No","Unknown"]
    r={"category":cat,"conscious":rng.choice(YNU,p=p["c"]),"breathing":rng.choice(YNU,p=p["b"]),
       "severe_bleeding":"NotAsked","chest_pain":"NotAsked","mobile":"NotAsked","weapon_involved":0}
    # note: probabilities for "No" mean problem; reorder so index1 = No
    r["conscious"]={"Yes":"Yes","No":"No","Unknown":"Unknown"}[r["conscious"]]
    if "bl" in p: r["severe_bleeding"]=rng.choice(["Yes","No","Unknown"],p=p["bl"])
    if "cp" in p: r["chest_pain"]=rng.choice(["Yes","No","Unknown"],p=p["cp"])
    if "mo" in p: r["mobile"]=rng.choice(["Free","Trapped","Unknown"],p=p["mo"])
    if "w" in p: r["weapon_involved"]=int(rng.random()<p["w"])
    r["people_count"]=int(rng.choice([1,2,3,4,5],p=p["pc"]))
    return r
def run_anchors():
    base=dict(category="",conscious="Yes",breathing="Yes",severe_bleeding="NotAsked",chest_pain="NotAsked",mobile="NotAsked",weapon_involved=0,people_count=1)
    def t(exp,**kw):
        r={**base,**kw}; got=to_label(risk_score(r))
        if protected(r): got="High"
        assert got==exp,(exp,got,kw)
    t("High",category="Security Threat",weapon_involved=1)
    t("Medium",category="Security Threat")
    for c in ("Yes","No","Unknown"): t("High",category="Abduction",conscious=c)
    t("High",category="Road Accident",mobile="Trapped",conscious="Unknown",severe_bleeding="No")
    t("Medium",category="Medical Emergency",severe_bleeding="No",chest_pain="No")
    t("Low",category="Road Accident",severe_bleeding="No",mobile="Free")
    t("High",category="Medical Emergency",conscious="No",severe_bleeding="No",chest_pain="No")
    t("High",category="Medical Emergency",breathing="No",severe_bleeding="No",chest_pain="No")
    t("High",category="Medical Emergency",chest_pain="Yes",severe_bleeding="No")
    t("High",category="Medical Emergency",severe_bleeding="Yes",chest_pain="No")
    t("Medium",category="Fire & Rescue",mobile="Free")
    t("High",category="Fire & Rescue",mobile="Trapped")
    t("High",category="Fire & Rescue",mobile="Unknown",conscious="Unknown")
    t("Low",category="Other / General")
    t("High",category="Other / General",conscious="No")
    t("Medium",category="Road Accident",severe_bleeding="No",mobile="Free",people_count=4)
    t("High",category="Road Accident",severe_bleeding="Yes",mobile="Free")
    t("High",category="Road Accident",breathing="Unknown",conscious="Unknown",severe_bleeding="No",mobile="Free")
    print("anchors: 19 checks passed")
def generate(n=3000):
    rng=np.random.default_rng(SEED); rows=[]
    for i in range(n):
        r=make_row(rng, CATS[rng.choice(6,p=[.28,.24,.14,.14,.05,.15])])
        sc=risk_score(r)+rng.normal(0,0.5)
        lab=to_label(sc)
        if protected(r): lab="High"
        r["risk_score"]=round(sc,2); r["label_was_noised"]=0
        if not protected(r) and rng.random()<0.08:
            up={"Low":"Medium","Medium":"High","High":"High"}; dn={"Low":"Low","Medium":"Low","High":"Medium"}
            new = up[lab] if rng.random()<0.7 else dn[lab]
            if new!=lab: lab=new; r["label_was_noised"]=1
        r["priority"]=lab; rows.append(r)
    return pd.DataFrame(rows)
if __name__=="__main__":
    run_anchors()
    df=generate(); df.to_csv("data/synthetic_triage_data.csv",index=False)
    print(df.priority.value_counts(normalize=True).round(3).to_dict()); print(pd.crosstab(df.category,df.priority))
    print("noised:",df.label_was_noised.mean().round(3))
