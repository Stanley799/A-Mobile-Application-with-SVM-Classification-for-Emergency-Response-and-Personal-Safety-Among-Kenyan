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
