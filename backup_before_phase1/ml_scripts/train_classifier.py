"""Train and compare classifiers, then save the best one.  Run:  py scripts\\train_classifier.py
Training data  = realistic rows + a balanced sample of the borderline combinations.
Test data      = realistic rows the model never saw (5-fold, repeated).  The full combination set is for test_combinations.py."""
import os, sys, json, time, platform, warnings, joblib, numpy as np, pandas as pd, sklearn
from sklearn.compose import ColumnTransformer
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler, OrdinalEncoder
from sklearn.linear_model import LogisticRegression
from sklearn.svm import SVC
from sklearn.ensemble import RandomForestClassifier
from sklearn.naive_bayes import CategoricalNB
from sklearn.model_selection import RepeatedStratifiedKFold
import triage_core as t
warnings.filterwarnings("ignore")

SEED, HIGH_KEEP = 42, 600
LABELS = t.PRIORITIES
df = pd.read_csv(os.path.join(t.ROOT, "data", "synthetic_triage_data.csv"))
R = df[df.sample_source == "realistic"].reset_index(drop=True)
C = df[df.sample_source == "coverage"]
boundary = pd.concat([C[C.priority != "High"], C[C.priority == "High"].sample(HIGH_KEEP, random_state=SEED)]).reset_index(drop=True)
print(f"realistic rows: {len(R)} | boundary sample from coverage: {len(boundary)} {boundary.priority.value_counts().to_dict()}")

AV = t.allowed_values()
def prep_onehot():
    return ColumnTransformer([("cat", OneHotEncoder(categories=[AV[f] for f in t.CATEGORICAL]), t.CATEGORICAL),
                              ("num", StandardScaler(), t.NUMERIC)])
def prep_ordinal():
    cats = [AV[f] for f in t.CATEGORICAL] + [list(range(1, 6)) for _ in t.NUMERIC]
    return ColumnTransformer([("o", OrdinalEncoder(categories=cats), t.CATEGORICAL + t.NUMERIC)])
def build(name):
    if name == "NaiveBayes (Bayesian baseline)":
        return Pipeline([("prep", prep_ordinal()), ("clf", CategoricalNB(alpha=1.0, min_categories=[len(c) for c in [AV[f] for f in t.CATEGORICAL]] + [5] * len(t.NUMERIC)))])
    clf = {"LogReg": LogisticRegression(max_iter=3000, C=1.0, class_weight="balanced"),
           "SVM-linear": SVC(kernel="linear", C=1, probability=True, class_weight="balanced", random_state=SEED),
           "SVM-RBF": SVC(kernel="rbf", C=1, probability=True, class_weight="balanced", random_state=SEED),
           "RandomForest": RandomForestClassifier(n_estimators=200, max_depth=10, class_weight="balanced", random_state=SEED)}[name]
    return Pipeline([("prep", prep_onehot()), ("clf", clf)])
NAMES = ["LogReg", "SVM-linear", "SVM-RBF", "RandomForest", "NaiveBayes (Bayesian baseline)"]

def floors(frame):
    return np.array([t.RANK[t.rule_floor(r)[0]] for r in frame[t.FEATURES].to_dict("records")])
def scores(y_true, y_pred_rank):
    yt = np.array([t.RANK[v] for v in y_true]); hi = yt == 2
    return dict(acc=float((yt == y_pred_rank).mean()), high_recall=float((y_pred_rank[hi] == 2).mean()),
                high_to_low=int(((yt == 2) & (y_pred_rank == 0)).sum()), high_to_med=int(((yt == 2) & (y_pred_rank == 1)).sum()))

report = {n: {"model_only": [], "hybrid": []} for n in NAMES}
cv = RepeatedStratifiedKFold(n_splits=5, n_repeats=2, random_state=SEED)
t0 = time.time()
for tr, te in cv.split(R, R.priority):
    train = pd.concat([R.iloc[tr], boundary]); test = R.iloc[te]
    fl = floors(test)
    for n in NAMES:
        m = build(n).fit(train[t.FEATURES], train.priority)
        P = m.predict_proba(test[t.FEATURES]); cl = list(m.classes_)
        pred = np.array([t.RANK[cl[i]] for i in P.argmax(axis=1)])
        biased = np.where(P[:, cl.index("High")] >= t.SCHEMA["high_threshold"], 2, pred)   # safety bias
        report[n]["model_only"].append(scores(test.priority, pred))
        report[n]["hybrid"].append(scores(test.priority, np.maximum(biased, fl)))
print(f"cross-validation took {time.time()-t0:.0f}s\n")
summary = {}
print(f"{'model':32s} {'mode':10s} {'acc':>6s} {'Highrecall':>10s} {'High->Low':>9s} {'High->Med':>9s}   (per test fold of {len(R)//5} cases)")
for n in NAMES:
    summary[n] = {}
    for mode in ("model_only", "hybrid"):
        s = {k: float(np.mean([f[k] for f in report[n][mode]])) for k in report[n][mode][0]}
        summary[n][mode] = s
        print(f"{n:32s} {mode:10s} {s['acc']:6.3f} {s['high_recall']:10.3f} {s['high_to_low']:9.2f} {s['high_to_med']:9.2f}")
# Selection rule (decided before looking at results): keep every model whose hybrid High->Low count is within
# 1.0 mistakes per test fold of the safest model (differences smaller than that are noise), then take the most
# accurate of those; on an exact tie prefer an SVM because the project is an SVM study.
safest = min(summary[k]["hybrid"]["high_to_low"] for k in NAMES)
candidates = [k for k in NAMES if summary[k]["hybrid"]["high_to_low"] <= safest + 1.0]
best = sorted(candidates, key=lambda k: (-round(summary[k]["hybrid"]["acc"], 3), not k.startswith("SVM")))[0]
print("candidates within 1.0 High->Low of the safest:", candidates)
print("\nSELECTED (safe enough, then most accurate):", best)

final_train = pd.concat([R, boundary])
final = build(best).fit(final_train[t.FEATURES], final_train.priority)
os.makedirs(os.path.join(t.ROOT, "models"), exist_ok=True)
joblib.dump(final, os.path.join(t.ROOT, "models", "priority_classifier.joblib"))
meta = {"schema_version": t.SCHEMA["version"], "model": best, "feature_order": t.FEATURES, "classes": list(final.classes_),
        "allowed_values": AV, "people_count_range": [1, 5], "confidence_floor": t.CONFIDENCE_FLOOR, "high_threshold": t.SCHEMA["high_threshold"],
        "trained_rows": int(len(final_train)), "python": platform.python_version(), "sklearn": sklearn.__version__,
        "pandas": pd.__version__, "joblib": joblib.__version__, "cv_summary": summary,
        "data_note": "Synthetic. Labels follow a documented scoring protocol with assumed weights. Not clinically validated."}
json.dump(meta, open(os.path.join(t.ROOT, "models", "metadata.json"), "w"), indent=2)
print("saved models/priority_classifier.joblib and models/metadata.json")
