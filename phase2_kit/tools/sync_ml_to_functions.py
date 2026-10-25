r"""Copies the ML files the Cloud Functions need from ml\ into functions\ml\. Run it from C:\EmergencyResponseSystem before every deploy:
    py tools\sync_ml_to_functions.py
It only copies (never edits) and prints a SHA-256 for each file, so you can see that the server runs exactly the files you tested."""
import hashlib, os, shutil, sys
ROOT = os.getcwd()
if not os.path.isdir(os.path.join(ROOT, "ml")) or not os.path.isdir(os.path.join(ROOT, "functions")):
    sys.exit("Run this from C:\\EmergencyResponseSystem (the folder that contains ml\\ and functions\\).")
FILES = ["scripts/triage_core.py", "scripts/dispatch_logic.py", "scripts/text_triage.py",
         "schema/triage_schema.json", "schema/lexicon.json", "schema/lexicon_ke.json", "schema/lexicon_user.json", "models/decision_table.json"]
OPTIONAL = ["scripts/feedback_store.py", "scripts/split_collected_messages.py"]   # only needed by save_text_feedback_fn
missing = [f for f in FILES if not os.path.exists(os.path.join(ROOT, "ml", f))]
if missing:
    sys.exit("Missing in ml\\: " + ", ".join(missing))
for f in FILES + [o for o in OPTIONAL if os.path.exists(os.path.join(ROOT, "ml", o))]:
    src, dst = os.path.join(ROOT, "ml", f), os.path.join(ROOT, "functions", "ml", f)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copy2(src, dst)
    print(f"  {f:34s} {hashlib.sha256(open(dst, 'rb').read()).hexdigest()[:16]}")
print("Done. functions\\ml now matches ml\\.")
for o in OPTIONAL:
    if not os.path.exists(os.path.join(ROOT, "ml", o)):
        print(f"  NOTE: ml\\{o} not found. save_text_feedback_fn will be skipped at deploy.")
