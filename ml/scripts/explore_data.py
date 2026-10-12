"""Draws 3 charts into the charts folder.  Run after run_all.py:  py scripts\\explore_data.py     (needs: py -m pip install matplotlib)"""
import os, pandas as pd, matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import triage_core as t
COL = {"Low": "#2E9E6B", "Medium": "#E0A21B", "High": "#D94A4A"}; ORDER = ["Low", "Medium", "High"]
os.makedirs(os.path.join(t.ROOT, "charts"), exist_ok=True)
df = pd.read_csv(os.path.join(t.ROOT, "data", "synthetic_triage_data.csv")); R = df[df.sample_source == "realistic"]
res = pd.read_csv(os.path.join(t.ROOT, "docs", "all_combinations_results.csv"))
ct = pd.crosstab(R.category, R.priority)[ORDER]
ax = ct.plot(kind="barh", stacked=True, color=[COL[c] for c in ORDER], figsize=(9, 4.5))
ax.set_title("Chart 1: priority mix per category (4,000 realistic synthetic cases)"); ax.set_xlabel("Number of cases"); ax.set_ylabel("")
plt.tight_layout(); plt.savefig(os.path.join(t.ROOT, "charts", "1_priority_by_category.png"), dpi=150); plt.close()
fig, axes = plt.subplots(1, 4, figsize=(14, 3.8), sharey=True)
for a, f in zip(axes, ["conscious", "breathing", "severe_bleeding", "trapped"]):
    s = R[R[f] != "NotAsked"].groupby(f).priority.apply(lambda x: (x == "High").mean()); a.bar(s.index, s.values, color="#0F766E"); a.set_title(f); a.set_ylim(0, 1)
axes[0].set_ylabel("Share labelled High"); plt.suptitle("Chart 2: how each answer changes the chance of High priority"); plt.tight_layout()
plt.savefig(os.path.join(t.ROOT, "charts", "2_high_share_by_answer.png"), dpi=150); plt.close()
cm = pd.crosstab(res.protocol_priority, res.final_priority).reindex(index=ORDER, columns=ORDER, fill_value=0)
fig, a = plt.subplots(figsize=(5.2, 4.6)); a.imshow(cm.values, cmap="Blues"); a.set_xticks(range(3), ORDER); a.set_yticks(range(3), ORDER)
a.set_xlabel("Decision table said"); a.set_ylabel("Protocol says")
for i in range(3):
    for j in range(3): a.text(j, i, int(cm.values[i, j]), ha="center", va="center", color="white" if cm.values[i, j] > cm.values.max() / 2 else "black")
a.set_title("Chart 3: ALL 16,740 answer combinations\nDangerous cell: Protocol High, Table Low (must be 0)"); plt.tight_layout()
plt.savefig(os.path.join(t.ROOT, "charts", "3_all_combinations_matrix.png"), dpi=150); plt.close()
print("Saved 3 charts in", os.path.join(t.ROOT, "charts"))
