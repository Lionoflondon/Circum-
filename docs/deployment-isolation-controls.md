# Deployment Isolation Controls

## Branch Protection

Protect `main` with:

- Required pull request reviews.
- Minimum two approving reviewers for deployment-control changes.
- No self approval.
- Required status checks:
  - `deploy_guard.self_test`
  - product-specific tests
  - artifact validation
- No force push.
- No direct push.

## IAM Isolation

Use separate CI deployment identities:

- `deploy-website`
- `deploy-sender-app`
- `deploy-rider-app`
- `deploy-admin`
- `deploy-functions`

Firebase Hosting IAM supports Hosting permissions such as site update and release permissions at the Firebase Hosting resource layer, but project setup must verify whether the required per-site restriction is enforceable for the current Firebase project and deployment tooling.

If per-site IAM cannot be enforced strongly enough, use separate Firebase projects for surfaces requiring hard credential separation.

## Shared Sign-Off

There is no permanent shared-file sign-off bypass in this repository.

The only shared files permitted by `deploy-manifest.json` are:

- `lib/app/security/circum_app_check.dart`
- `scripts/deploy_isolated.sh`
- `scripts/firebase_tools.sh`

Adding a fourth shared file fails `scripts/deploy_guard.self_test.js`.

## Blocked Legacy Paths

Legacy Sender Web deployment paths are explicitly blocked in `deploy-manifest.json`.
They are not owned by Sender App or Website deployments. If one changes, `scripts/deploy_guard.js` fails before build or deploy.

## Continuous Audit

Every deployment workflow runs:

- `node scripts/deploy_guard.self_test.js`
- `node scripts/deploy_guard.js --target=<product>`
- product-specific tests
- product-specific build
- artifact validator
