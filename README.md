Emergency Response and Personal Safety System

Phase 1 implements environment setup, Firebase backend configuration, and public authentication for Kenya-based Residents and responder organizations.

The current mobile app also includes a resident dashboard with SOS alert creation, safety check-ins, trusted contacts, activity history, and profile editing. These resident workflows are a later implementation slice; the original Phase 1 exclusions below describe the historical Phase 1 scope.

## Phase 1 Scope

Implemented:

- Firebase initialization for the Flutter app.
- Email/password registration and login.
- Public roles: `Resident` and `Responder`.
- SystemAdmin support only through the one-off local `createFirstAdmin` script.
- Firestore rules for `users`, `responders`, and `auditLogs`.
- Cloud Functions for role claims and immutable audit logging.
- Role-based routing with distinct responder verification screens.
- Android and iOS permission declarations plus role-aware permission requests.

Not implemented in Phase 1:

- Incidents.
- Dispatch.
- Trusted contacts.
- Safety check-ins.
- Hospital-specific workflows.
- Separate facilities or HospitalAdmin roles.

## Firebase Collections

Registration uses these collections:

- `users`, with document ID equal to Firebase Auth UID.
- `responders`, with document ID equal to the linked user UID.

Resident features also use:

- `trustedContacts` for owner-managed contacts. Removal is a soft delete using `isActive: false`.
- `safetyCheckins` for timed check-ins and their status history. Documents cannot be deleted by clients.
- `incidents` for SOS alert submissions, with optional location captured only during an SOS flow. Owners may cancel an alert, but cannot change the submitted incident details.

Client queries and writes for these resident collections are scoped to the authenticated owner by Firestore rules. Cloud Functions also write `auditLogs` for forensic readiness. Client writes to `auditLogs` are denied by Firestore rules.

Responder organizations include these organization types only: `Ambulance`, `Fire`, `Police`, `Hospital`, `Community`, `Maritime`, and `Other`.

## Setup

1. Install Flutter and confirm the toolchain:

	```powershell
	flutter doctor
	```

2. Install Flutter dependencies:

	```powershell
	Set-Location mobile
	flutter pub get
	```

3. Install Cloud Functions dependencies:

	```powershell
	Set-Location ..\functions
	npm install
	```

4. Validate Firestore rules and indexes without deploying:

	```powershell
	Set-Location ..
	firebase deploy --only firestore:rules,firestore:indexes --dry-run --project emergencyresponsesystem-166601
	```

5. Run static analysis:

	```powershell
	Set-Location mobile
	flutter analyze
	```

6. Run the app:

	```powershell
	flutter run
	```

## Deploy Backend

Deploy Firestore rules and Cloud Functions from the repository root:

```powershell
firebase deploy --only firestore:rules,functions --project emergencyresponsesystem-166601
```

The Functions backend uses Node.js 20 in Firebase. Local Node.js 24 may show an engine warning during `npm install`; deployment runtime remains Node.js 20.

## Profile And Password Recovery

The resident profile supports an explicit edit mode, validation, a before/after change review, confirmed saves, and confirmed discard. Failed saves keep the user's edits. Conflicting edits to the same fields on another device are rejected rather than overwritten. Email, role, and account status remain protected; account deletion is not part of this workflow.

Profile photos can be selected from the device, taken with the camera on Android/iOS, cropped with zoom/pan, previewed, and confirmed before upload. Users can replace, recrop, or remove their photo later. The upload is a 512 x 512 JPEG with original metadata removed. Photos are stored privately under `profilePhotos/{uid}/{photoId}.jpg`; the profile document stores the relative `profilePhotoPath`, not a public download URL. Storage rules allow owner-only access and enforce a 2 MB upload limit. Old photos and rolled-back uploads are deleted on a best-effort basis; temporary network failures may leave an unreferenced private object for later administrative cleanup.

Password recovery is available from `Forgot password?` on sign-in and `Reset password` in the profile. Firebase sends the reset email and handles the reset link using its hosted action page. The app uses a neutral response that does not reveal whether an account exists, a resend cooldown, and retryable network errors. No reset tokens or passwords are stored in Firestore. Client cooldowns are a usability safeguard, not a replacement for Firebase's service-side abuse controls.

### Firebase Setup Required

1. In the project's Firebase console, open **Storage** and complete **Get started**. The bucket was not configured during implementation. Review billing requirements and choose a region consistent with the application's data-protection commitments.
2. From the repository root, validate and deploy the profile rules after bucket setup:

	```powershell
	firebase deploy --only firestore:rules,storage --dry-run --project emergencyresponsesystem-166601
	firebase deploy --only firestore:rules,storage --project emergencyresponsesystem-166601
	```

3. In **Authentication**, verify that email/password sign-in is enabled, enable email-enumeration protection, and review the password-reset email template, sender branding, authorized domains, and password policy. Keep the policy consistent with registration requirements.
4. On a real device, verify camera/photo-library permissions, crop and replacement, removal, and private loading. Send a reset email to a controlled test account and verify link completion, expiration/reuse rejection, and subsequent sign-in. No real reset emails were sent during automated tests.

The Android picker and lifecycle implementations are pinned to avoid introducing a plugin-specific requirement above the configured API 23 minimum. Recheck native minimum SDK requirements before upgrading those packages. Rebuild the app after installing the new plugins; hot reload alone does not register them. Native compatibility on API 23 remains unverified: the installed Flutter SDK attempted to migrate the minimum SDK setting during the build, and the project's original setting was restored.

The debug APK build was blocked by the missing Android NDK `28.2.13676358` and a crash in the local SDK manager. Install that NDK through Android Studio's SDK Manager, repair/update the command-line tools as needed, then rerun the build. No successful APK build or real-device verification is claimed.

### Validation And References

```powershell
Set-Location mobile
flutter test test/profile_screen_test.dart
flutter test
flutter analyze
flutter build apk --debug
```

Focused tests cover save confirmation, retained edits on failure, private photo replacement/removal, rollback, stale-edit rejection, metadata removal, crop preview/cancellation on a narrow viewport, and password-reset validation/cooldown/error handling. Firestore rules passed compilation; Storage rule validation and live uploads require the bucket setup above.

- Firebase user management: https://firebase.google.com/docs/auth/flutter/manage-users
- Firebase Storage conditions: https://firebase.google.com/docs/storage/security/rules-conditions
- OWASP password recovery guidance: https://cheatsheetseries.owasp.org/cheatsheets/Forgot_Password_Cheat_Sheet.html
- Flutter image picker: https://pub.dev/packages/image_picker
- Image cropping: https://pub.dev/packages/crop_your_image

## Create the First SystemAdmin

SystemAdmin accounts are never created by the public Flutter app. They are created once, locally, by a developer using the Admin SDK script at `functions/scripts/createFirstAdmin.js`.

1. Download a Firebase service account key and save it as `functions/serviceAccountKey.json`. This file is ignored by Git.

2. Set required environment variables:

	```powershell
	Set-Location functions
	$env:GOOGLE_APPLICATION_CREDENTIALS = "serviceAccountKey.json"
	$env:ADMIN_EMAIL = "admin@example.com"
	$env:ADMIN_PASSWORD = "UseAStrongPasswordHere"
	$env:ADMIN_PHONE_NUMBER = "+254712345678"
	$env:ADMIN_FIRST_NAME = "System"
	$env:ADMIN_LAST_NAME = "Administrator"
	$env:ADMIN_DOB_ISO = "1990-01-01"
	$env:ADMIN_GENDER = "PreferNotToSay"
	$env:ADMIN_PREFERRED_LANGUAGE = "en"
	npm run create:first-admin
	```

The script refuses to run if any existing Auth user or `users` document already has the `SystemAdmin` role. It creates one Firebase Auth account, sets the `role: "SystemAdmin"` custom claim, creates the matching `users` document, and writes an audit log entry.

## KDPA Cross-Border Consent Rationale

Firebase services may process and store data on infrastructure outside Kenya. The registration flow therefore requires explicit consent before account creation, using a clear Kenya Data Protection Act, 2019 disclosure. The Phase 1 schema minimizes personal data to identity, contact, preferred language, consent, date of birth, gender, and role-specific responder organization data needed for verification and future emergency response workflows.

## Security Notes

- Authorization uses Firebase Auth custom claims and Firestore rules from day one.
- Client code cannot write `auditLogs`.
- Public registration creates only `Resident` or `Responder` users.
- Responder verification fields are writable only by a `SystemAdmin` custom claim.
- Responder owner updates are limited to `availabilityStatus`, `currentLatitude`, and `currentLongitude`.
- Responder organization identity fields are allowed only at creation and are immutable to the owner afterward.
- Resident contact, check-in, and incident records are owner-scoped; contacts are soft-deleted and incident details are immutable to clients. Owners may update only an incident's status to `Cancelled` and its update timestamp.
- Profile editing is limited to first name, last name, phone number, and preferred language. Email, role, and account status are display-only.
- Phone numbers are checked against libphonenumber metadata in the client and stored in E.164 form. Firestore rules validate E.164 syntax only; they cannot establish that a number is active or assigned.
- Location is not captured during registration. The SOS flow requests current location after its cancellable countdown and still sends the alert if location is unavailable or permission is denied.

## Responder Verification

**Responder Registration Number**

The registration number is the organization's official Business Registration Number from the Registrar of Companies (for private companies) or the NGO Coordination Board (for non-profits). It is typed manually by the responder during registration and verified by a SystemAdmin against the KMPDC public register at https://registers.kmpdc.go.ke.

This field is immutable after creation. Neither the responder nor the SystemAdmin can change it once the document exists. If a correction is needed, the document must be deleted and recreated, which is intentional to preserve the audit trail.

## Useful References

- Firebase Authentication custom claims: https://firebase.google.com/docs/auth/admin/custom-claims
- Cloud Firestore security rules: https://firebase.google.com/docs/firestore/security/get-started
- Cloud Functions for Firebase Firestore triggers: https://firebase.google.com/docs/functions/firestore-events
- Kenya Office of the Data Protection Commissioner: https://www.odpc.go.ke/
