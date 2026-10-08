# Emergency Activation System Implementation Report

## Overview
This report records the implementation of the emergency activation system for the resident app. The solution covers the three activation paths, a rule-based priority classifier stub, triage question flow, and the Firestore schema expected by the dispatcher workflow.

## Completed Work

### 1. Core domain models and schema
- Added support for emergency enums including categories, priorities, activation paths, and incident lifecycle states.
- Added the typed incident model that maps to Firestore and preserves legacy fields used by the current app.

### 2. Rule-based classifier contract
- Implemented the priority classifier interface and a rule-based stub that matches the research-driven rules:
  - unconscious or non-breathing cases are prioritized as High
  - weapon involvement triggers High priority
  - trapped incidents in road accidents or fires escalate to High
  - multiple affected people move to at least Medium

### 3. Resident emergency activation flow
- Added the full-screen countdown for the SOS path with haptic feedback and cancel handling.
- Added the category-based triage sheet with a branching question flow and final priority suggestion confirmation.
- Added the free-text emergency option with keyword extraction and priority suggestion.
- Added the active incident confirmation screen that appears after an incident is saved. The current backend does not implement dispatch or confirm responder assignment.

### 4. Firestore and app behavior integration
- Updated the resident dashboard to trigger the correct path based on the selected action.
- Ensured incidents are created with the required schema, including category, priority, timestamps, and activation path.
- Added compatibility with the existing app's legacy `userId` field and the new `reporterId` shape required by the new design.

### 5. Security rules
- Expanded the Firestore incident rules to allow creation for signed-in users, ownership checks, support for cancellation, and admin review.

### 6. Dependencies
- Added the `uuid` dependency for stable incident IDs.
- Used Flutter's built-in `HapticFeedback` API rather than a third-party package, as required by the design.

## Validation
The rule-based classifier was validated with a focused regression test covering:
- unconscious patient escalation to High
- trapped road accident escalation to High

The test command used was:

```bash
cd c:/EmergencyResponseSystem/mobile && flutter test test/priority_classifier_test.dart
```

This was initially failing because the classifier and models did not yet exist, and after implementation it passes once the new files are included.

## Notes
The design intentionally preserves the current resident dashboard while integrating the new activation architecture. This allows the app to support the emergency flow without breaking the existing authentication, profile, and contact features.

## SOS Flow Corrections

- Confirmed cancellation returns to the previous screen only after the incident update succeeds. Failed cancellation remains on the alert screen with an error and retry action.
- Replaced triage uncertainty options with `Not sure`. Selecting one records the answer and advances, including questions whose uncertainty value is null.
- Added an answer review summary with per-question editing. Editing preserves other answers and recalculates the suggested priority.
- Made description submission reactive to text changes, scrollable around the keyboard, and retryable after classifier errors. The confirmation screen includes the original description.
- Converted triage enums to Firestore-compatible values without changing the in-memory answers.
- Corrected optional-field rule checks so omitted fields do not deny valid incident submissions.
- Prevented navigation to the success screen when persistence fails. Location-service errors now fall back to sending without location.
- Changed the success message to `Emergency alert sent` rather than promising an unconfirmed responder or dispatcher call.

### Verification

Mobile regression coverage includes each category's confirmation result, uncertainty advancement, review/edit preservation, cancellation success and failure, classifier retries, a small-screen keyboard layout, and incident serialization.

From the mobile directory:

```powershell
flutter test --no-pub
flutter analyze --no-pub
```

The updated Firestore rules passed Firebase's compilation dry run. Behavioral security tests are provided in `functions/test/incident_rules.test.js`; they require Java and a local Firestore emulator. From the repository root:

```powershell
firebase emulators:exec --only firestore --project demo-emergencyresponse "node --test functions/test/incident_rules.test.js"
```

The emulator tests use a demo project and reject execution against a non-demo project. The current session could not run them because both emulator artifact download attempts were interrupted by the network. No rules were deployed to production; deployment of the optional-field fix is required before live validation.

### References

- Flutter text change callbacks: https://docs.flutter.dev/cookbook/forms/text-field-changes
- Flutter scrolling and constrained layouts: https://docs.flutter.dev/ui/layout/scrolling
- Firestore optional fields and restricted updates: https://firebase.google.com/docs/firestore/security/rules-fields
