import json, joblib, pandas as pd
model=joblib.load("models/priority_classifier.joblib"); meta=json.load(open("models/metadata.json"))
ALLOWED=meta["allowed_values"]; ORDER=meta["feature_order"]; FLOOR=meta["confidence_floor"]
def suggest_priority(payload):
    p=dict(payload); p["weapon_involved"]=int(bool(p.get("weapon_involved",0)))
    p["people_count"]=max(1,min(5,int(p.get("people_count",1))))
    for f in ALLOWED:
        if p.get(f) not in ALLOWED[f]: raise ValueError(f"Invalid {f}: {p.get(f)!r}")
    X=pd.DataFrame([[p[f] for f in ORDER]],columns=ORDER)
    pr=model.predict_proba(X)[0]; cls=list(model.classes_); i=pr.argmax()
    return {"priority":cls[i],"confidence":round(float(pr[i]),3),"needs_human_review":bool(pr[i]<FLOOR),"probabilities":{c:round(float(v),3) for c,v in zip(cls,pr)}}
if __name__=="__main__":
    b=dict(category="",conscious="Yes",breathing="Yes",severe_bleeding="NotAsked",chest_pain="NotAsked",mobile="NotAsked",weapon_involved=0,people_count=1)
    tests=[("armed security",dict(category="Security Threat",weapon_involved=1)),
     ("abduction",dict(category="Abduction")),
     ("medical unconscious",dict(category="Medical Emergency",conscious="No",severe_bleeding="No",chest_pain="No")),
     ("medical chest pain",dict(category="Medical Emergency",chest_pain="Yes",severe_bleeding="No")),
     ("minor road",dict(category="Road Accident",severe_bleeding="No",mobile="Free")),
     ("fire trapped",dict(category="Fire & Rescue",mobile="Trapped")),
     ("other all fine",dict(category="Other / General")),
     ("medical all fine",dict(category="Medical Emergency",severe_bleeding="No",chest_pain="No"))]
    for n,t in tests: print(f"{n:22s}",suggest_priority({**b,**t}))
    try: suggest_priority({**b,"category":"Fire and Rescue"})
    except ValueError as e: print("typo rejected:",e)
