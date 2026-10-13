"""Feature importance AUDIT (a sanity check, not a selection step).   py scripts\\feature_importance.py

WHAT IT DOES
  1. Permutation importance: shuffle ONE question's answers (only among cases of the same category, so 'NotAsked' stays valid)
     and measure how much the saved model's balanced accuracy drops. Big drop = the model relies on that question.
  2. Mutual information: a simple statistical link between each question and the priority label (a 'filter' method).
  3. Protocol weight: the largest weight the scoring protocol gives that question (schema/triage_schema.json).
  4. Spearman rank correlation between (1) and (3).

HOW TO READ IT (important)
  The training labels were produced by the scoring protocol from THESE SAME questions. So a high correlation only shows that the
  model LEARNED THE PROTOCOL. It is NOT evidence that a question is medically important. Only real labelled data could show that.
  'category' is reported but not permuted: it decides which other questions exist, so shuffling it makes impossible cases."""
import os
import numpy as np
import pandas as pd
import joblib
from sklearn.metrics import balanced_accuracy_score
from sklearn.feature_selection import mutual_info_classif
from scipy.stats import spearmanr
import triage_core as t

SEED, REPEATS = 42, 10
rng = np.random.default_rng(SEED)
model = joblib.load(os.path.join(t.ROOT, "models", "priority_classifier.joblib"))
df = pd.read_csv(os.path.join(t.ROOT, "data", "synthetic_triage_data.csv"))
R = df[df.sample_source == "realistic"].reset_index(drop=True)
X, y = R[t.FEATURES].copy(), R["priority"]
base = balanced_accuracy_score(y, model.predict(X))
print(f"Rows used: {len(R)} realistic cases | baseline balanced accuracy of the saved model: {base:.3f}\n")

# 1. permutation importance (within category so the NotAsked structure stays valid)
perm = {}
for f in t.FEATURES:
    if f == "category":
        continue
    drops = []
    for _ in range(REPEATS):
        Xp = X.copy()
        for _, idx in R.groupby("category").groups.items():
            Xp.loc[idx, f] = rng.permutation(X.loc[idx, f].to_numpy())
        drops.append(base - balanced_accuracy_score(y, model.predict(Xp)))
    perm[f] = (float(np.mean(drops)), float(np.std(drops)))

# 2. mutual information (discrete codes)
codes = pd.DataFrame({f: pd.factorize(X[f])[0] for f in t.FEATURES})
mi = dict(zip(t.FEATURES, mutual_info_classif(codes, y, discrete_features=True, random_state=SEED)))

# 3. protocol weight: the largest weight the scoring protocol can add for that question
W = t.SCHEMA["weights"]
proto = {}
for f in t.FEATURES:
    if f == "category":
        vals = [v["value"] for v in W["baseline"].values()]; proto[f] = max(vals) - min(vals)
    elif f == "people_count":
        proto[f] = max(v["value"] for v in W["people_count"].values())
    else:
        proto[f] = max(v["value"] for v in W["answers"][f].values())

rows = []
for f in t.FEATURES:
    rows.append({"feature": f, "permutation_drop": None if f == "category" else round(perm[f][0], 4),
                 "permutation_sd": None if f == "category" else round(perm[f][1], 4), "mutual_information": round(float(mi[f]), 4),
                 "protocol_max_weight": round(proto[f], 2)})
out = pd.DataFrame(rows).sort_values("permutation_drop", ascending=False, na_position="first")
print(out.to_string(index=False))
sub = out.dropna(subset=["permutation_drop"])
rho, p = spearmanr(sub["permutation_drop"], sub["protocol_max_weight"])
print(f"\nSpearman rank correlation, permutation drop vs protocol weight (11 questions): rho = {rho:.2f} (p = {p:.3f})")
print("A high rho means the model learned the protocol. It does NOT prove the questions are medically important.\n")
out.to_csv(os.path.join(t.ROOT, "docs", "feature_importance.csv"), index=False)
print("Saved docs\\feature_importance.csv")
try:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    os.makedirs(os.path.join(t.ROOT, "charts"), exist_ok=True)
    s = sub.sort_values("permutation_drop")
    fig, a = plt.subplots(figsize=(8, 4.8))
    a.barh(s["feature"], s["permutation_drop"], xerr=s["permutation_sd"], color="#0F766E")
    a.set_xlabel("Drop in balanced accuracy when the question is shuffled (higher = model relies on it more)")
    a.set_title("Chart 4: what the model relies on (audit, not feature selection)\nlabels come from the same protocol, so this shows the model learned the protocol")
    plt.tight_layout(); plt.savefig(os.path.join(t.ROOT, "charts", "4_feature_importance.png"), dpi=150); plt.close()
    print("Saved charts\\4_feature_importance.png")
except ImportError:
    print("matplotlib not installed: chart skipped (py -m pip install matplotlib)")
