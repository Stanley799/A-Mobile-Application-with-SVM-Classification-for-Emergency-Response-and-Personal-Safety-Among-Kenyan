r"""Applies the ML side of Phase 1B. Safe to run twice. Run from C:\EmergencyResponseSystem:  py phase1b_kit\apply_ml_update.py
It never touches ml\data\ files you own, never runs run_all.py, and backs up every file it replaces."""
import hashlib, json, os, shutil, sys, time
KIT = os.path.dirname(os.path.abspath(__file__))
ROOT = os.getcwd()
ML = os.path.join(ROOT, "ml")
if not os.path.isdir(ML):
    sys.exit("Run this from C:\\EmergencyResponseSystem (the folder that contains ml\\ and mobile\\).")
BK = os.path.join(ROOT, "backup_phase1b_" + time.strftime("%Y%m%d_%H%M%S"))
def backup(path):
    if os.path.exists(path):
        dst = os.path.join(BK, os.path.relpath(path, ROOT)); os.makedirs(os.path.dirname(dst), exist_ok=True); shutil.copy2(path, dst)
def put(rel_src, rel_dst):
    src = os.path.join(KIT, rel_src); dst = os.path.join(ROOT, rel_dst)
    backup(dst); os.makedirs(os.path.dirname(dst), exist_ok=True); shutil.copy2(src, dst); print("  copied", rel_dst)
for f in ["ml/scripts/text_triage.py", "ml/scripts/eval_text_multi.py", "ml/scripts/export_text_rules.py",
          "ml/schema/lexicon_ke.json", "ml/data/text_eval_sw.csv", "ml/data/text_eval_sw2.csv", "ml/data/text_eval_sw3.csv"]:
    put(f, f)
# 1) the one built-in test in YOUR lexicon_user.json whose expected answer changed (guarded: exact text, exact count)
p = os.path.join(ML, "schema", "lexicon_user.json")
s = open(p, encoding="utf-8").read()
old = '"text": "amekosa fahamu baada ya ajali",\n   "category": null'
new = '"text": "amekosa fahamu baada ya ajali",\n   "category": "Road Accident"'
if s.count(old) == 1:
    backup(p); open(p, "w", encoding="utf-8", newline="").write(s.replace(old, new)); print("  lexicon_user.json: 1 test line updated")
elif s.count(new) == 1:
    print("  lexicon_user.json: already updated")
else:
    s2 = s.replace("\r\n", "\n")
    if s2.count(old) == 1:
        backup(p); open(p, "w", encoding="utf-8", newline="").write(s2.replace(old, new)); print("  lexicon_user.json: 1 test line updated")
    else:
        print("  lexicon_user.json: test line not found as expected. NOT changed. Tell me; this is not fatal.")
# 2) evaluate_text.py: it used the old classifier-in-the-middle design
p = os.path.join(ML, "scripts", "evaluate_text.py")
s = open(p, encoding="utf-8").read()
old = 'run("lexicon only", use_classifier=False); run("classifier only", use_lexicon=False)\nfails = run("combined (used)")'
new = 'run("lexicon only", use_classifier=False); run("classifier only", use_lexicon=False, use_classifier=True)\nfails = run("engine as shipped")'
if old in s.replace("\r\n", "\n"):
    backup(p); open(p, "w", encoding="utf-8", newline="").write(s.replace("\r\n", "\n").replace(old, new)); print("  evaluate_text.py updated")
else:
    print("  evaluate_text.py: already updated or different. Not changed.")
print("Backup of replaced files:", BK)
print("Next: py ml\\scripts\\check_lexicon.py ; py ml\\scripts\\eval_text_multi.py ; py ml\\scripts\\test_robustness.py ; py ml\\scripts\\export_text_rules.py")
