Emergency Response and Personal Safety System

Phase 1 implements environment setup, Firebase backend configuration, and public authentication for Kenya-based Residents and responder organizations.

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

The public app writes only these registration collections:

- `users`, with document ID equal to Firebase Auth UID.
- `responders`, with document ID equal to the linked user UID.

Cloud Functions also write `auditLogs` for forensic readiness. Client writes to `auditLogs` are denied by Firestore rules.

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

4. Validate Firestore rules without deploying:

	```powershell
	Set-Location ..
	firebase deploy --only firestore:rules --dry-run --project emergencyresponsesystem-166601
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

## Useful References

- Firebase Authentication custom claims: https://firebase.google.com/docs/auth/admin/custom-claims
- Cloud Firestore security rules: https://firebase.google.com/docs/firestore/security/get-started
- Cloud Functions for Firebase Firestore triggers: https://firebase.google.com/docs/functions/firestore-events
- Kenya Office of the Data Protection Commissioner: https://www.odpc.go.ke/
