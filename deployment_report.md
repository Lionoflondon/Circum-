# SAFE RELEASE REPORT

## Sender App

NOT SAFE

Changed files:
- .github/workflows/deploy_sender_web.yml
- lib/app/authentication/bloc/auth_bloc.dart
- lib/app/iris/iris_learning_bridge.dart
- lib/app/security/circum_app_check.dart
- lib/app/send_package/bloc/send_package_bloc.dart
- lib/app/sender_mobile/gift_journey_draft.dart
- lib/app/sender_mobile/gift_story_view.dart
- lib/app/sender_mobile/gift_voice_note_view.dart
- lib/app/sender_mobile/sender_mobile_home.dart
- lib/app/sender_mobile/sender_mobile_preview.dart
- lib/app/support/bloc/support_bloc.dart
- lib/app/support/view/chat.dart
- lib/app/support/view/support.dart
- lib/main.dart
- lib/messaging.dart
- scripts/build_sender_app_web.sh
- test/sender_mobile/sender_notification_routing_test.dart
- lib/app/media/circum_media.dart
- lib/app/sender_mobile/sender_startup_diagnostics.dart
- lib/app/sender_mobile/sender_startup_diagnostics_stub.dart
- lib/app/sender_mobile/sender_startup_diagnostics_web.dart
- test/sender_mobile/gift_voice_media_contract_test.dart
- test/sender_mobile/sender_startup_diagnostics_test.dart

Reasons:
- deploy command: Mobile app publishing is manual.

## Sender Web

SAFE

Changed files:
- .github/workflows/deploy_sender_web.yml
- lib/app/authentication/bloc/auth_bloc.dart
- lib/app/iris/iris_learning_bridge.dart
- lib/app/security/circum_app_check.dart
- lib/app/send_package/bloc/send_package_bloc.dart
- lib/app/sender_mobile/gift_journey_draft.dart
- lib/app/sender_mobile/gift_story_view.dart
- lib/app/sender_mobile/gift_voice_note_view.dart
- lib/app/sender_mobile/sender_mobile_home.dart
- lib/app/sender_mobile/sender_mobile_preview.dart
- lib/app/support/bloc/support_bloc.dart
- lib/app/support/view/chat.dart
- lib/app/support/view/support.dart
- lib/main.dart
- lib/messaging.dart
- scripts/build_sender_app_web.sh
- test/sender_mobile/sender_notification_routing_test.dart
- lib/app/media/circum_media.dart
- lib/app/sender_mobile/sender_startup_diagnostics.dart
- lib/app/sender_mobile/sender_startup_diagnostics_stub.dart
- lib/app/sender_mobile/sender_startup_diagnostics_web.dart
- test/sender_mobile/gift_voice_media_contract_test.dart
- test/sender_mobile/sender_startup_diagnostics_test.dart
- deploy-manifest.json
- firebase.json
- scripts/deploy_guard.self_test.js
- scripts/deploy_isolated.sh
- scripts/finalize_web_artifact.js
- scripts/validate_web_artifacts.js
- test/security/circum_app_check_contract_test.dart
- test/web_artifact_isolation_test.dart
- deployment_report.md
- safe_release.sh
- scripts/release_orchestrator.js
- .github/workflows/rc1_release_build.yml
- PRODUCTION_DIAGNOSTICS.md

## Public Website

SAFE

Changed files:
- .github/workflows/deploy_website.yml
- lib/website/shared/circum_website_app.dart
- lib/website/shared/security/circum_website_app_check.dart
- scripts/build_public_web.sh
- scripts/deploy_public_web.sh
- deploy-manifest.json
- firebase.json
- scripts/deploy_guard.self_test.js
- scripts/deploy_isolated.sh
- scripts/finalize_web_artifact.js
- scripts/validate_web_artifacts.js
- test/security/circum_app_check_contract_test.dart
- test/web_artifact_isolation_test.dart
- deployment_report.md
- safe_release.sh
- scripts/release_orchestrator.js
- .github/workflows/rc1_release_build.yml

## Admin

SAFE

Changed files:
- lib/app/admin/admin_phase1_shell.dart
- lib/app/admin/security/admin_app_check.dart
- lib/main_admin_web.dart
- test/admin_operations_test.dart
- deploy-manifest.json
- firebase.json
- scripts/deploy_guard.self_test.js
- scripts/deploy_isolated.sh
- scripts/finalize_web_artifact.js
- scripts/validate_web_artifacts.js
- test/security/circum_app_check_contract_test.dart
- test/web_artifact_isolation_test.dart
- deployment_report.md
- safe_release.sh
- scripts/release_orchestrator.js
- .github/workflows/rc1_release_build.yml

## Cloud Functions

NOT SAFE

Changed files:
- server/functions/account-closure.js
- server/functions/account-closure.test.js
- server/functions/communication-engine.js
- server/functions/communication-engine.test.js
- server/functions/gift-story-automation.js
- server/functions/gift-story-automation.test.js
- server/functions/gifts-payment-finalization-contract.test.js
- server/functions/gifts-payment.js
- server/functions/health-plus-checkout-security.test.js
- server/functions/health-plus.js
- server/functions/index.js
- server/functions/iris-core.js
- server/functions/iris-core.test.js
- server/functions/send-message.js
- server/functions/sender-account.js
- server/functions/admin-governance.js
- server/functions/admin-governance.test.js
- server/functions/gift-voice-media.js
- server/functions/gift-voice-media.test.js
- server/functions/rider-account.js
- server/functions/rider-account.test.js
- deploy-manifest.json
- firebase.json
- scripts/deploy_guard.self_test.js
- scripts/deploy_isolated.sh
- scripts/finalize_web_artifact.js
- scripts/validate_web_artifacts.js
- test/security/circum_app_check_contract_test.dart
- test/web_artifact_isolation_test.dart
- deployment_report.md
- safe_release.sh
- scripts/release_orchestrator.js
- .github/workflows/rc1_release_build.yml

Reasons:
- deploy command: Requires an explicit scoped function list.

## Storage Rules

SAFE

Changed files:
- storage.rules

## Untouched Targets

- Firestore Rules: NO CHANGES
- Indexes: NO CHANGES
- Rider: NO CHANGES

## Deploy Summary

Deployable: 4
Skipped: 3
Blocked: 2
Mode: changed
Generated: 2026-07-22T02:49:34.273Z

## Change Classification

- admin: 4
- ci: 1
- diagnostics: 1
- documentation: 5
- functions: 21
- release-tooling: 11
- sender: 23
- storage-rules: 1
- website: 5
