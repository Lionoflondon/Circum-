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

Runtime startup independently probes named-database read access and requires an actual PERMISSION_DENIED for a non-customer probe in the default database. It refuses to start otherwise. Public release also requires this isolationVerified health flag at the exact approved SHA.

The builder uses E2_MEDIUM because this project rejects the high-CPU regional builder. The dedicated runtime must pass its real IAM isolation probe and exact-SHA health check before the canonical TEST owner is staged. Traffic targets the explicit SHA-derived staged revision, never a possibly stale latestReadyRevisionName.

## Restricted LIVE certification candidate

TEST certification must independently prove automatic signed delivery, provider retry, exactly one canonical credit and receipt, and isolation. The candidate deploy script requires that report, the exact protected main SHA, a private UID allowlist, pinned LIVE-only secrets, and the reviewed containment baseline. Public LIVE stays disabled.

The LIVE service reads the default database and must be denied the named TEST database. It validates the merchant, verified account owner, wallet ownership, freeze state and balance agreement before issuing or finalizing Checkout. Return pages only read status. TEST and LIVE capabilities use different browser storage and endpoints.

Healthy Stripe and password-recovery email owners use immutable existing images with one-file overlays. The build rejects source hash drift; original source SHAs and other routes stay intact. Website artifacts delegate to the dedicated owner; existing refund handlers remain unchanged. The email publisher excludes the dedicated website receipt. Run `python3 scripts/prepare_roth_live_overlays.py` and `node scripts/test_roth_live_overlays.cjs` before release. Generated overlay files are build artifacts.

Publish `/roth/live-cert/` using `enable_roth_live_candidate=true`, `enable_roth_test=true` and the independently certified TEST runtime SHA. This is an explicitly versioned interface pair; it does not redeploy TEST or native apps. The LIVE endpoint permits only the private account. Complete a real purchase through a human-controlled payment step and reconcile delivery, wallet, ledger and email before setting public mode with the exact certified source SHA. Public Hosting activation requires matching healthy public LIVE runtime. Never bypass that gate or release held queues.
