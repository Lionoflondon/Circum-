# Website ROTH TEST release

Only Website, dedicated `circum-website-roth-test` runtime and the required delegation guard in the existing canonical TEST webhook are released. Sender/Rider and LIVE webhook services are excluded. Startup refuses LIVE keys, LIVE enablement, any database except `roth-website-test`, and a missing approved UID allowlist.

API challenges, orders, balances, canonical ledger and outbox use the named TEST database. The existing ledger receives this database explicitly. Firebase Auth remains the registered identity authority. The dedicated endpoint processes website ROTH orders only; subscribe to checkout.session.completed, checkout.session.async_payment_succeeded and checkout.session.async_payment_failed. Keep existing owners unchanged.

The runtime sends only its own OTP/receipt records using the existing branded worker and deterministic provider idempotency keys. No held queue, Eventarc subscription or shared email service is changed.

Status is authenticated and read-only. It waits for the webhook even if Stripe reports paid. Cancellation expires an unpaid open checkout. Logout revokes the verification capability and clears local state; fresh OTP login restores the same account balance.

## Release procedure

Provision the dedicated TEST database and approved isolated fixtures. Independently verify database permissions, public App Check and TEST key/account/endpoint secret bindings. Use protected merged main and preserve current caps/holds throughout.

Private `ROTH_TEST_ENV_FILE` YAML must contain WEBSITE_ROTH_ENABLED=true, WEBSITE_ROTH_LIVE=false, STRIPE_MODE=test, FIRESTORE_DATABASE_ID=roth-website-test, and WEBSITE_ROTH_TEST_UIDS listing approved identities only. Do not put secret values in this file.

Supply ROTH_CONTAINMENT_BASELINE (reviewed snapshot with exact25 names), ROTH_TEST_IMAGE_REPOSITORY (existing project repository), ROTH_TEST_OTP_VERSION and ROTH_TEST_WEBHOOK_VERSION (dedicated pinned secret versions). Run `scripts/deploy_website_roth_test.sh <exact-approved-current-main-sha>`.

The script checks containment and prerequisites, creates a clean temporary checkout, builds only Dockerfile.website-roth, deploys only circum-website-roth-test at min0/max1 and rechecks containment. It first verifies the existing canonical TEST owner and stages its narrowly scoped website delegation guard, preserving TEST secrets/settings, before changing that TEST owner traffic. It never changes LIVE services or deploys Functions. Existing TEST Stripe key version2 must be verified privately before running.

Verify the new runtime before dispatching the existing Deploy Website workflow at the same SHA with enable_roth_test=true. It deploys hosting:public only and uses Public Website App Check. Other website releases keep purchases disabled by default.

## Certification

Fresh deployed website checkout, real approved OTP, Stripe TEST card. Capture independent provider delivery, named database before/after balances and one canonical ledger/outbox; compare relevant default database records read-only. Verify exactly one inbox receipt, refresh/logout/login, account denial and invalid/unpaid/failed/cancelled cases. Prove real provider retry after a controlled isolated temporary failure and duplicate/delayed idempotency. Unit/emulator tests do not substitute for deployed/provider evidence.

Preserve GBP6 CONFIGURED, GBP5 ENFORCED, exact25 holds, retry manual0 and #579 zero traffic. No LIVE configuration changes or unrelated deployments. Stop before a release gate that cannot be safely met.

The dedicated runtime service identity is `circum-website-roth-test`. Its datastore.user grant must use the documented IAM condition `resource.name=="projects/circum-2797c/databases/roth-website-test"`; no default-database write grant is permitted. Grant Firebase Auth viewer for registered identity lookup and Secret Manager access only to TEST key version2, dedicated OTP/webhook versions and the existing email-provider secret. No LIVE key access.

For real provider retry certification, the operator may arm exactly one approved session with `{remaining:1}` in the named database's websiteRothCertificationFailures/sessionId document before paying. The signed TEST webhook atomically consumes this fixture and returns500 once before credit; subsequent automatic delivery processes normally. There is no public fixture route. Record both automatic attempts and do not manually replay to prove retry.

Website checkout and PaymentIntent metadata explicitly identify the named TEST database. The canonical TEST owner must deploy the signed-event delegation guard before any new website purchase, preventing TEST review/ledger records in the default database. The dedicated website owner remains the only financial finalizer.
