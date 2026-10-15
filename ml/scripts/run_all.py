"""Runs every step in the right order and stops at the first failure.  Run from the ml folder:  py scripts\\run_all.py
Everything printed is ALSO saved to docs\\run_log.txt: that file is your EVIDENCE (date, Python version, every result)."""
import subprocess
import sys
import os
import time
import platform
import datetime

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.abspath(os.path.join(here, ".."))
STEPS = [("1/13 Generate synthetic data (23 safety checks run first)", "generate_synthetic_data.py"),
         ("2/13 Train and compare models (cross-validation)", "train_classifier.py"),
         ("3/13 Compile the decision table", "build_decision_table.py"),
         ("4/13 Test EVERY answer combination", "test_combinations.py"),
         ("5/13 Test responder matching and briefing", "test_dispatch_logic.py"),
         ("6/13 Check the lexicon files (lint + built-in tests)", "check_lexicon.py"),
         ("7/13 Train the text classifier", "train_text_classifier.py"),
         ("8/13 Evaluate the text path", "evaluate_text.py"),
         ("9/13 Robustness and safe-fallback tests", "test_robustness.py"),
         ("10/13 Draw the exploration charts", "explore_data.py"),
         ("11/13 Feature importance audit (about 1-2 minutes)", "feature_importance.py"),
         ("12/13 Generate Flutter constants", "generate_dart.py"),
         ("13/13 Write app-versus-Python parity test cases", "make_test_vectors.py")]

try:
    sys.stdout.reconfigure(errors="replace")            # a Windows console must never crash on a special character
except AttributeError:
    pass
os.makedirs(os.path.join(root, "docs"), exist_ok=True)
with open(os.path.join(root, "docs", "run_log.txt"), "w", encoding="utf-8") as log:
    def say(text):
        sys.stdout.write(text)
        sys.stdout.flush()
        log.write(text)
        log.flush()

    say(f"Run started {datetime.datetime.now():%Y-%m-%d %H:%M:%S} | Python {sys.version.split()[0]} | {platform.platform()}\n")
    env = {**os.environ, "PYTHONIOENCODING": "utf-8"}
    for title, script in STEPS:
        say("\n" + "=" * 78 + "\n" + title + "\n" + "=" * 78 + "\n")
        t0 = time.time()
        p = subprocess.Popen([sys.executable, "-W", "ignore", "-X", "utf8", os.path.join(here, script)], stdout=subprocess.PIPE,
                             stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace", env=env)
        for line in p.stdout:
            say(line)
        p.wait()
        if p.returncode != 0:
            say(f"\nSTOPPED: {script} failed (exit code {p.returncode}). Copy the text above and send it to your assistant.\n")
            sys.exit(1)
        say(f"[{script} finished in {time.time() - t0:.0f}s]\n")
    say("\nALL STEPS COMPLETED\n")
