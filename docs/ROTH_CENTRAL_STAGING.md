# Central ROTH staging connector

This branch adds an App Check enforced callable bridge for CIRCUM's company-scoped ROTH merchant identity. It is separate from the existing CIRCUM wallet paths and is disabled unless the deployed function is explicitly configured for a non-production staging project.

## Guarded callable operations

- `beginRothAccountLink` starts a five-minute ROTH identity-link request using the authenticated CIRCUM UID.
- `getRothCentralCompanyBalance` reads CIRCUM's company allocation for the authenticated linked identity.
- `issueRothFromCircum` permits an active company administrator to issue an idempotent reward against a verified linked identity.

All requests are server-signed and use the staging-only ROTH API origin. The merchant signing secret is a Firebase Secret Manager parameter and is never returned to clients or logged. The reward endpoint validates an integer-pence amount and a stable reference.

## Required staging configuration

- `ROTH_CENTRAL_MODE=staging`.
- `ROTH_COMPANY_STAGING_PROJECT` must exactly match the deployed Firebase project and must use a staging/dev/test project identifier. `circum-2797c` is explicitly rejected.
- `ROTH_CENTRAL_API_ORIGIN=https://roth-stage-api-77403622757.europe-west2.run.app`.
- `ROTH_CIRCUM_MERCHANT_KEY_ID` and Secret Manager secret `ROTH_CIRCUM_MERCHANT_SECRET`, provisioned with company-scoped `identities:link`, `wallet:read`, and `rewards:issue` permissions.

The current CIRCUM repository baseline points Firebase at `circum-2797c`; that is not an approved staging target. No deployment or project change is included here. Referral event routing, Sender/Rider UI, delivery reservations/settlement, refund paths, and retirement of legacy issuance remain cutover work and must be completed before this bridge is enabled.
