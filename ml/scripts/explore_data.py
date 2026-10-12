"""Draws 3 charts from the synthetic data into the 'charts' folder. Run from the ml folder: py scripts\\explore_data.py"""
import os, pandas as pd, numpy as np, joblib, matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from sklearn.base import clone
from sklearn.model_selection import cross_val_predict, StratifiedKFold
from sklearn.metrics import confusion_matrix
ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
if not os.path.exists(os.path.join(ROOT, "data")): ROOT = os.getcwd()
os.makedirs(os.path.join(ROOT, "charts"), exist_ok=True)
df = pd.read_csv(os.path.join(ROOT, "data", "synthetic_triage_data.csv"))
model = joblib.load(os.path.join(ROOT, "models", "priority_classifier.joblib"))
COL = {"Low": "#2E9E6B", "Medium": "#E0A21B", "High": "#D94A4A"}
ORDER = ["Low", "Medium", "High"]
# 1. Priority mix per category
ct = pd.crosstab(df.category, df.priority)[ORDER]
ax = ct.plot(kind="barh", stacked=True, color=[COL[c] for c in ORDER], figsize=(9, 4.5))
ax.set_title("Priority mix per category (synthetic data)"); ax.set_xlabel("Number of cases"); ax.set_ylabel("")
plt.tight_layout(); plt.savefig(os.path.join(ROOT, "charts", "1_priority_by_category.png"), dpi=150); plt.close()
# 2. Share of High cases by answer
fig, axes = plt.subplots(1, 4, figsize=(14, 3.8), sharey=True)
for a, f in zip(axes, ["conscious", "breathing", "severe_bleeding", "chest_pain"]):
    s = df[df[f] != "NotAsked"].groupby(f).priority.apply(lambda x: (x == "High").mean())
    a.bar(s.index, s.values, color="#0F766E"); a.set_title(f); a.set_ylim(0, 1)
axes[0].set_ylabel("Share labelled High")
plt.suptitle("How each answer changes the chance of High priority"); plt.tight_layout()
plt.savefig(os.path.join(ROOT, "charts", "2_high_share_by_answer.png"), dpi=150); plt.close()
# 3. Confusion matrix on unseen cases (5-fold cross-validation, NOT the training score)
X = df[["category","conscious","breathing","severe_bleeding","chest_pain","mobile","weapon_involved","people_count"]]
pred = cross_val_predict(clone(model), X, df.priority, cv=StratifiedKFold(5, shuffle=True, random_state=0))
cm = confusion_matrix(df.priority, pred, labels=ORDER)
fig, a = plt.subplots(figsize=(5, 4.5)); a.imshow(cm, cmap="Blues")
a.set_xticks(range(3), ORDER); a.set_yticks(range(3), ORDER); a.set_xlabel("Model said"); a.set_ylabel("Label was")
for i in range(3):
    for j in range(3): a.text(j, i, cm[i, j], ha="center", va="center", color="white" if cm[i, j] > cm.max()/2 else "black")
a.set_title("Confusion matrix (unseen cases)\nDangerous cell: Label High, Model Low"); plt.tight_layout()
plt.savefig(os.path.join(ROOT, "charts", "3_confusion_matrix.png"), dpi=150); plt.close()
print("Saved 3 charts in", os.path.join(ROOT, "charts"))
