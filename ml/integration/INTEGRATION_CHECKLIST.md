# Integration checklist (schema 3.1.0, written against your real app in C:\EmergencyResponseSystem\mobile)

Rule: **the `ml` folder is the single source of truth.** Never edit `lib\core\triage\*` or `assets\decision_table.json` by hand.
Change `ml`, run `py scripts\run_all.py`, copy again.

## How the flow works (what you built)

1. Resident taps a category (or the big SOS button) -> your existing 5-second countdown -> the alert is created **immediately**
   with `priority: High`, `prioritySource: safe_fallback`, `needsHumanReview: true`, `triageStatus: pending` (the fail-safe).
2. A "Quick details" sheet opens. Other / General starts with an optional description box (the server suggests a type, the resident confirms).
   Then: what best describes it (subtype) -> the category's questions (one tap each) -> optional extra detail -> Done.
3. The same incident is **updated** with subtype, answers, priority (from the decision table, works offline), `triageStatus: complete`.
4. If the resident taps Skip or closes the sheet, the alert simply stays High and flagged for a person. Nothing is lost.
5. Emotional distress: asks "Are you thinking of harming yourself?". Yes -> mental health crisis (High). No -> `status: SupportOnly`, support lines shown.
6. Confidential subtypes (sexual violence, domestic violence, mental health crisis, emotional distress): what the resident typed is never stored on the incident and never saved for training.

## Part A. Flutter app (works offline)

| # | Do this | Check |
|---|---------|-------|
| A1 | `py scripts\run_all.py` in `ml` ends with `ALL STEPS COMPLETED` (step 13 prints "exhaustive: 112185 ... disagrees on 0"). | |
| A2 | From `C:\EmergencyResponseSystem`: `mkdir mobile\assets, mobile\test\assets, mobile\lib\core\triage -Force` | |
| A3 | `copy ml\models\decision_table.json mobile\assets\` | |
| A4 | `copy ml\dart\triage_schema.dart mobile\lib\core\triage\` and `copy ml\dart\triage_lookup.dart mobile\lib\core\triage\` | |
| A5 | Extract `mobile_kit.zip` into `C:\EmergencyResponseSystem\mobile` (replaces `home_screen.dart` and `pubspec.yaml`; adds the new files). Do A3-A4 AFTER this so your own generated files win. | |
| A6 | `cd mobile` then `flutter pub get` | |
| A7 | `flutter analyze`. **Send me every error line** (there may be a few; I could not compile Flutter where I wrote this). | |
| A8 | Tests: `copy ml\models\decision_table.json mobile\test\assets\` and `copy ml\integration\test_vectors.json mobile\test\assets\`, then `flutter test test\triage_parity_test.dart`. Must pass. | |
| A9 | Run the app on a phone or emulator. Walk through: a Road Accident, an Other / General with text, Security Threat -> Sexual violence (1195 must show), Other -> Feeling very distressed -> No. | |
| A10 | In the Firebase console open `incidents`: the incident has `priority`, `triage.answers`, `triageStatus: complete`. Tap Skip on a second one: it stays `pending`, `High`. | |
| A11 | Airplane mode: the questions and priority still work (Firestore saves when the network returns). | |

## Part B. Cloud Functions (text suggestion and saving real messages)

Without this part the app still works. The description box just shows "We couldn't suggest a type right now" and the resident picks by hand.

| # | Do this | Check |
|---|---------|-------|
| B1 | In `mobile`: `firebase init functions` -> Python. (Needs the Blaze plan; it has a free monthly allowance, but ask before you enable billing.) | |
| B2 | Copy `ml\scripts`, `ml\schema`, `ml\models` into `functions\ml\`. Copy `ml\integration\functions_main.py` -> `functions\main.py`. | |
| B3 | `functions\requirements.txt`: `firebase-functions`, `firebase-admin`, `scikit-learn==<same version as py -m pip show scikit-learn>`, `joblib`, `numpy`. | |
| B4 | `firebase functions:secrets:set FEEDBACK_SALT` (any long random text; never change it later). | |
| B5 | Region is `europe-west1` in both `functions\main.py` and `lib\core\services\triage_text_service.dart`. If you change one, change both. | |
| B6 | Paste `ml\integration\firestore_rules_snippet.txt` into your Firestore rules and deploy them. **Check your existing rules also let a resident update only their own incident**, otherwise the final update is refused (the alert still exists and stays High). | |
| B7 | Test: type "I want to kill myself" with the consent box ticked. Nothing may appear in Firestore `text_feedback`. Type "lorry overturned on the highway" with consent: it appears. Without consent: nothing appears. | |

## Part C. Real-data loop (any time, after Part B)

`py scripts\import_app_messages.py C:\path\to\serviceAccountKey.json` -> `py scripts\split_collected_messages.py --force` -> `py scripts\run_all.py` -> `py scripts\evaluate_text.py data\real_messages.csv`.
Service-account key: Firebase console > Project settings > Service accounts > Generate new private key. Keep it outside the project folder.
Only the text classifier learns from real messages. The priority model never retrains by itself.

## Part D. Contract for the dispatch function you will build next (write this in Chapter 4)

- `triageStatus: pending` means "treat as High". If it is still pending after about 60 seconds, dispatch as High.
- `Other / General` incidents may become `SupportOnly` within that minute; check the status again before sending a responder.
- Re-check the priority on the server with `triage_priority_fn` (the phone could be tampered with) and use the higher of the two.
- Never show or send `description` for confidential subtypes (it is not stored, but keep the rule).
- Always show 922; show 1195 for sexual or domestic violence. Keep 999/112/116 off until verified.

## Part E. Before you call it done

1. Copy `docs/safety_nets_and_error_handling.md` section 4 into the thesis limitations.
2. One person with emergency-care training reviews `docs/all_combinations_results.csv` and floors F01-F10; write their name and date down.
3. Test on a real phone in airplane mode (Part A, A11).
