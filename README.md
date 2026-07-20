# Circum

Circum contains the Sender application, Circum Website, Admin, and the
canonical Circum backend. The Rider mobile application is maintained in the
separate Circum-Rider repository and must not be modified from this repository.

## Product Boundaries

- Sender App: `lib/main.dart`, `lib/app/sender_mobile/**`, Sender-owned mobile
  flows, and Sender-owned shared infrastructure.
- Circum Website: `lib/main_public_web.dart`, `lib/website/**`, and the shared
  website shell for Sender Web and Rider Web.
- Admin: `lib/main_admin_web.dart` and `lib/app/admin/**`.
- Backend: `server/functions/**`, `firestore.rules`, and `storage.rules`.

Run the deployment guard before any release:

```sh
node scripts/deploy_guard.self_test.js
node scripts/deploy_guard.js --target=sender-app --base HEAD
node scripts/deploy_guard.js --target=website --base HEAD
node scripts/deploy_guard.js --target=admin --base HEAD
node scripts/deploy_guard.js --target=backend --base HEAD
```

## Local Validation

```sh
flutter pub get
flutter analyze
flutter test
npm --prefix server/functions ci
npm --prefix server/functions run lint
npm --prefix server/functions test
git diff --check
```

Firestore Rules tests require the Firebase emulator and a local Java runtime:

```sh
npm --prefix server/functions run test:rules
```

## App Check

Sender mobile initializes Firebase App Check through
`lib/app/security/circum_app_check.dart`.

- Android production provider: Play Integrity.
- iOS production provider: App Attest with DeviceCheck fallback.
- Web provider: reCAPTCHA Enterprise.

Web builds must receive the shared web App Check key as a build-time
environment value. Never commit or print the key.

```sh
CIRCUM_WEB_RECAPTCHA_ENTERPRISE_SITE_KEY=<site-key> scripts/build_public_web.sh
CIRCUM_WEB_RECAPTCHA_ENTERPRISE_SITE_KEY=<site-key> scripts/build_sender_app_web.sh
CIRCUM_WEB_RECAPTCHA_ENTERPRISE_SITE_KEY=<site-key> scripts/build_admin_web.sh
```

Firebase Console App Check enforcement is a manual rollout decision and is not
enabled by repository changes.

## Google Maps Keys

Maps runtime keys are configuration values, not source constants.

- Android Maps SDK: `GOOGLE_MAPS_API_KEY` Gradle property or environment
  variable, injected into `android/app/src/main/AndroidManifest.xml`.
- iOS Maps SDK: `GOOGLE_MAPS_API_KEY` build setting, read by
  `ios/Runner/AppDelegate.swift`.
- Directions API: `GOOGLE_MAPS_DIRECTIONS_API_KEY` passed with
  `--dart-define` for Sender route calculations.

Manual Google Cloud Console checklist:

- Restrict Android Maps key to the Sender package name and production signing
  SHA fingerprints.
- Restrict iOS Maps key to the Sender bundle identifier.
- Restrict web Maps keys by HTTP referrer for approved Circum domains only.
- Restrict each key to only the APIs it needs.
- Disable unused Maps APIs.
- Do not rotate keys from repository tasks; rotation is an operations task.

## Historical Credentials

Do not commit service account keys, Stripe secrets, webhook secrets, App Check
site keys, or Google Maps keys. If historical credentials were ever committed,
do not rewrite history from this repository task. Use the manual cloud checklist:

- Audit Firebase IAM service accounts.
- Disable or delete unused service account keys.
- Rotate any exposed webhook or API secrets.
- Confirm GitHub Actions secrets contain only current production values.
- Confirm old local `.env` files are not used by production deployments.

## CI

`.github/workflows/ci.yml` runs Flutter analysis/tests, Functions lint/tests,
Firestore emulator Rules tests, and product isolation guards. Deployment
workflows remain separate and must not be used to bypass CI.
