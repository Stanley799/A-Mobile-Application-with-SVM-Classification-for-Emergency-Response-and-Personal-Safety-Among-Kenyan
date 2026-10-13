START HERE
1. Put this folder at C:\EmergencyResponseSystem\ml
2. Open PowerShell and type:   cd C:\EmergencyResponseSystem\ml
3. Install once:               py -m pip install -r requirements.txt
4. Run everything:             py scripts\run_all.py
5. Draw charts (optional):     py scripts\explore_data.py
6. Read docs\Triage_Dispatch_Design_Specification.docx  (Part B repeats these steps and explains each one)

Folders: schema (the single source of truth), scripts, data, models, docs, dart (files for Flutter), charts.
Edit only: schema\triage_schema.json, schema\lexicon_user.json, data\text_training_user.csv, data\real_messages.csv.
Always run from the ml folder, not from the scripts folder.


------------------------------------------------------------------------------
UPDATE (text triage version 2, schema 3.1.0)
------------------------------------------------------------------------------
New files: scripts\check_lexicon.py, scripts\merge_proposed.py, schema\lexicon_proposed.json,
           docs\lexicon_review.csv, docs\text_triage_architecture.md
After editing schema\lexicon_user.json always run:   py scripts\check_lexicon.py
To use the assistant's proposed Swahili terms: read docs\lexicon_review.csv, delete what you disagree with in
schema\lexicon_proposed.json, ask a native speaker about the PROPOSED_MEDIUM rows, then run   py scripts\merge_proposed.py
New subtype emotional_distress (heartbreak, stress, grief): no responder is dispatched; the app must ask the safety question.

------------------------------------------------------------------------------
UPDATE 13 Oct 2026: evidence, collection kit, feature audit
------------------------------------------------------------------------------
py scripts\run_all.py now has 11 steps and saves EVERYTHING it prints to docs\run_log.txt (your evidence: date, versions, results).
New: scripts\feature_importance.py (docs\feature_importance.csv, charts\4_feature_importance.png). It is an audit, not a selection step.
New collection kit: docs\message_collection_guide.md, data\collection_scenarios.csv, data\collected_master_template.csv,
                    scripts\split_collected_messages.py  (splits BY PERSON into text_training_user.csv and real_messages.csv)

--- UPDATE (13 Oct, design audit) ---
* Protocol guard added: the model can raise a priority, never lower it below the protocol (0 under-triage in all 16,740 combinations).
* predict_priority.suggest_priority_safe() and Dart lookupSafe(): any error returns High + human review. Use these in production.
* Safety flags tolerate one typo (suicde, molestd).
* New: scripts/test_robustness.py (step 9 of run_all.py), docs/safety_nets_and_error_handling.md.
* docs/message_collection_guide.md now explains the 3 files with a worked example.
