# Release Candidate 1 Readiness

Status: architecture frozen for RC1.

This release gate allows only:

- CI lint fixes.
- Reproducible App Check configuration fixes.
- Release documentation.
- Deployment repeatability fixes.

No feature development, UI redesign, or architecture refactor belongs in RC1
stabilisation.

## Required Verification

Run these gates before tagging RC1:

```bash
npm --prefix server/functions run lint
npm --prefix server/functions test
flutter analyze --no-fatal-warnings --no-fatal-infos
flutter test
git diff --check
node scripts/deploy_guard.self_test.js
node scripts/absolute_product_ownership.js
node scripts/validate_web_artifacts.js --surface=sender-app
node scripts/validate_web_artifacts.js --surface=website
node scripts/validate_web_artifacts.js --surface=admin
```

Firestore Rules verification requires a local Java runtime because the Firebase
emulator starts a Java process:

```bash
java --version
npm --prefix server/functions run test:rules
```

If local Java is unavailable, classify that as an environment blocker, not a
product blocker. CI installs Temurin Java 21 through `actions/setup-java@v4`
before running rules tests.

## App Check Gate

Before release, verify live Sender and Rider startup logs have no:

- `appCheck/recaptcha-error`
- `exchangeRecaptchaEnterpriseToken`
- Firebase App Check 403 startup failures

Google Maps JavaScript async-loading recommendations are tracked separately
from App Check and are not an App Check release blocker.

## Deployment Repeatability

Use the dedicated RC1 workflow. It rebuilds the Sender Web, Public Website and
Admin artifacts from GitHub secrets, deploys only Firestore Rules, the explicit
scoped Cloud Functions export list, Sender Web, Public Website and Admin, and
does not deploy Rider:

```bash
gh workflow run rc1_deploy.yml --ref <release-branch>
gh run watch <run-id> --exit-status
```

The local safe-release report remains available for target classification:

```bash
./safe_release.sh changed
```

Deploy only through green release gates. Do not force deploy or bypass
deployment guards.

## RC1 Tagging

Create the release candidate tag only after all required gates pass:

```bash
git tag -a rc1 -m "Release Candidate 1"
git push origin rc1
```
