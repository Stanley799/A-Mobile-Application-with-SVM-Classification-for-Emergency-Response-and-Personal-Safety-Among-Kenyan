mobile_kit.zip  - extract INTO C:\EmergencyResponseSystem\mobile  (it keeps the lib\ and test\ folder structure)

NEW files:   lib\core\models\triage_outcome.dart
             lib\core\services\priority_classifier.dart        (was empty)
             lib\core\services\triage_text_service.dart
             lib\features\resident\widgets\triage_question_sheet.dart   (was empty)
             lib\features\resident\widgets\other_free_text_sheet.dart   (was empty)
             lib\features\resident\widgets\hotline_card.dart
             lib\core\triage\triage_schema.dart, triage_lookup.dart     (generated; overwrite with YOUR ml\dart copies, see checklist A4)
             test\triage_parity_test.dart
CHANGED:     lib\features\resident\screens\home_screen.dart   (only: 3 imports + the alert/triage part of _confirmEmergency)
             pubspec.yaml   (only: url_launcher dependency + assets: assets/decision_table.json)
NOT touched: every other file, including the other empty ones (incident.dart, emergency_enums.dart, emergency_active_screen.dart, sos_countdown_sheet.dart).

Then follow ml\integration\INTEGRATION_CHECKLIST.md, Part A.
