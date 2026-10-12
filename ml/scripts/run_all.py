"""Runs every step in the right order and stops at the first failure.  Run from the ml folder:  py scripts\\run_all.py"""
import subprocess, sys, os
here = os.path.dirname(os.path.abspath(__file__))
STEPS = [("1/8 Generate synthetic data (23 safety checks run first)", "generate_synthetic_data.py"),
         ("2/8 Train and compare models", "train_classifier.py"),
         ("3/8 Compile the decision table", "build_decision_table.py"),
         ("4/8 Test EVERY answer combination", "test_combinations.py"),
         ("5/8 Test responder matching and briefing", "test_dispatch_logic.py"),
         ("6/8 Train the text classifier", "train_text_classifier.py"),
         ("7/8 Evaluate the text path", "evaluate_text.py"),
         ("8/8 Generate Flutter constants", "generate_dart.py")]
for title, script in STEPS:
    print("\n" + "=" * 78 + "\n" + title + "\n" + "=" * 78, flush=True)
    r = subprocess.run([sys.executable, "-W", "ignore", os.path.join(here, script)])
    if r.returncode != 0:
        print(f"\nSTOPPED: {script} failed. Copy the red text above and send it to your assistant."); sys.exit(1)
print("\nALL STEPS COMPLETED")
