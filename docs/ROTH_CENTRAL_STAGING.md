# Central ROTH staging connector

This isolated branch adds an App Check enforced callable bridge for CIRCUM's company-scoped ROTH merchant identity and central referral-award support. It is separate from the existing CIRCUM wallet paths and is disabled unless the deployed function is explicitly configured for a non-production staging project.

## Guarded callable operations

- `beginRothAccountLink` starts a five-minute ROTH identity-link request using the authenticated CIRCUM UID.
- `getRothCentralCompanyBalance` reads CIRCUM's company allocation for the authenticated linked identity.
- `issueRothFromCircum` permits an active company administrator to issue an idempotent reward against a verified linked identity.
- The Cloud Run referral event handler can issue both inviter and referred-customer rewards to central ROTH. Each recipient has a stable reward reference, amounts are converted to integer pence, and the synthetic staging reward cap is £10. An unlinked identity or failed API call remains reviewable and retryable; it never falls back to CIRCUM's local ledger in that handler.
- When central staging mode is selected, all referral award paths fail closed unless the scoped central client is injected; legacy direct referral-ledger writes are disabled for that runtime. Retry-state writes also preserve an already-awarded referral if concurrent handlers finish out of order.

## Sender account linking UI

- The Sender wallet's Roth information action opens the central ROTH link flow only when both `ROTH_CENTRAL_STAGING_ENABLED=true` and `ROTH_COMPANY_STAGING_PROJECT=<verified-isolated-project-id>` are supplied at build time, and the initialized Firebase app project exactly matches that configured project. The production project `circum-2797c`, mismatched project IDs, and non-staging project names fail the client gate; the default build has the feature disabled.
- The customer creates a five-minute link code in Sender, approves the named CIRCUM account from the ROTH customer app, then returns to Sender to refresh the CIRCUM allocation. The client displays only the verified central allocation and reservations returned by the authenticated callable; it never copies or stores a balance locally.
- This adds account linking and allocation visibility only. It does not yet route Sender/Rider checkout, delivery reservations, cancellations, refunds, or legacy wallet balances through central ROTH. Those flows remain disabled from central staging until their end-to-end server transaction and migration safeguards are implemented and tested.

All requests are server-signed and use the staging-only ROTH API origin. The merchant signing secret is a Firebase Secret Manager parameter and is never returned to clients or logged. The reward endpoint validates an integer-pence amount and a stable reference.

## Required staging configuration

- `ROTH_CENTRAL_MODE=staging`.
- `ROTH_COMPANY_STAGING_PROJECT` must exactly match the deployed Firebase project and must use a staging/dev/test project identifier. `circum-2797c` is explicitly rejected.
- `ROTH_CENTRAL_API_ORIGIN=https://roth-stage-api-77403622757.europe-west2.run.app`.
- `ROTH_CIRCUM_MERCHANT_KEY_ID` and Secret Manager secret `ROTH_CIRCUM_MERCHANT_SECRET`, provisioned with company-scoped `identities:link`, `wallet:read`, and `rewards:issue` permissions.
- For a separately deployed staging referral-event service, its Firestore event source must match the service's exact `GCLOUD_PROJECT`/`ROTH_COMPANY_STAGING_PROJECT`; the service must receive the same CIRCUM-scoped merchant secret from Secret Manager. Production event source remains fixed to `circum-2797c`.

The current CIRCUM repository baseline points Firebase at `circum-2797c`; that is production and is not an approved staging target. No deployment or project change is included here. Referral event routing, Sender/Rider wallet UI, delivery reservations/settlement, refund paths, legacy-ledger cutover and partner acceptance remain outstanding. Do not enable central staging mode until an isolated CIRCUM staging project, signed ROTH merchant credential, customer identity links and an explicit staging deployment target have been verified.
