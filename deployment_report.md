# SAFE RELEASE REPORT

## Sender App

MANUAL

Changed files:
- lib/app/sender_mobile/sender_booking_canvas.dart
- lib/app/sender_mobile/sender_mobile_profile.dart
- test/sender_mobile/sender_mobile_profile_test.dart
- test/sender_mobile/sender_tracking_state_web_test.dart

Reasons:
- deploy command: Mobile app publishing is manual.

## Sender Web

SAFE

Changed files:
- lib/app/sender_mobile/sender_booking_canvas.dart
- lib/app/sender_mobile/sender_mobile_profile.dart
- test/sender_mobile/sender_mobile_profile_test.dart
- test/sender_mobile/sender_tracking_state_web_test.dart
- deploy-manifest.json
- deployment_report.md
- scripts/absolute_product_ownership.js
- scripts/release_orchestrator.js
- scripts/scoped_functions_deploy_list.js
- .github/workflows/deploy_functions.yml
- .github/workflows/rc1_deploy.yml

## Public Website

SAFE

Changed files:
- lib/website/shared/circum_website_app.dart
- deploy-manifest.json
- deployment_report.md
- scripts/absolute_product_ownership.js
- scripts/release_orchestrator.js
- scripts/scoped_functions_deploy_list.js
- .github/workflows/deploy_functions.yml
- .github/workflows/rc1_deploy.yml

## Admin

SAFE

Changed files:
- deploy-manifest.json
- deployment_report.md
- scripts/absolute_product_ownership.js
- scripts/release_orchestrator.js
- scripts/scoped_functions_deploy_list.js
- .github/workflows/deploy_functions.yml
- .github/workflows/rc1_deploy.yml

## Cloud Functions

SAFE

Changed files:
- server/functions/.eslintrc.js
- server/functions/accept-ride-requests.js
- server/functions/accept-ride-requests.test.js
- server/functions/admin-operations-authority.js
- server/functions/business-centre-contract.test.js
- server/functions/core-payment-amount-security.test.js
- server/functions/firestore-live-tracking-rules.test.js
- server/functions/founder-rider-access.test.js
- server/functions/free-address-core.test.js
- server/functions/index.js
- server/functions/iris-security.test.js
- server/functions/package.json
- server/functions/payments-cancellation-contract.test.js
- server/functions/rider-presence-core.test.js
- server/functions/rider-vehicle-snapshot.js
- server/functions/roth-financial-invariants.test.js
- server/functions/send-package.js
- server/functions/sender-account-authority.test.js
- server/functions/sender-booking-drafts.test.js
- server/functions/sender-booking.js
- server/functions/sender-tracking-state-core.js
- server/functions/sender-tracking-state-core.test.js
- server/functions/admin-operations-authority-contract.test.js
- server/functions/firestore-sender-trust-rules.test.js
- server/functions/sender-profile-trust-contract.test.js
- deploy-manifest.json
- deployment_report.md
- scripts/absolute_product_ownership.js
- scripts/release_orchestrator.js
- scripts/scoped_functions_deploy_list.js
- .github/workflows/deploy_functions.yml
- .github/workflows/rc1_deploy.yml

## Firestore Rules

SAFE

Changed files:
- firestore.rules

## Rider

EXTERNAL

Changed files:
- test/rider_dispatch_offer_contract_test.dart

Reasons:
- repository: Owned by Circum-Rider repository

## Untouched Targets

- Storage Rules: NO CHANGES
- Indexes: NO CHANGES

## Deploy Summary

Deployable: 5
Skipped: 4
Blocked: 0
Mode: changed
Generated: 2026-08-01T07:11:43.068Z

## Change Classification

- ci: 2
- documentation: 1
- firestore-rules: 1
- functions: 25
- release-tooling: 5
- rider-external: 1
  - test/rider_dispatch_offer_contract_test.dart
- sender: 4
- website: 1
