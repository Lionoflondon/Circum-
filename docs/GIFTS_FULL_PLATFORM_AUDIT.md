# CIRCUM Gifts platform audit

Audit date: 2026-09-26  
Source baseline: `3db856d50c7b5ee9329fd6b1947016f362ef3f71` (`main` at audit start)  
Audit branch: `codex/gifts-full-platform-audit-20260926`  
Scope: Gifts for me, Gifts for others, Business Gifts, campaigns, payments/Roth, idempotency, email, privacy/Story, Admin and production ownership.  
Email boundary: audit existing templates only. No email template or copy has been created or modified.

## Executive result

**BLOCKED for a full production certification/deployment.** Two low-risk source fixes are prepared on this branch: campaign-match approval is now designed to be replay-safe, and the Business dashboard no longer presents a fabricated recipient-status count. They still need protected CI, review/merge, and eligible narrow deployment before they can be called fixed in production.

The source and production identities do not currently align: the live Gifts payment-family image is `84417e3b2486c136a9014652032b5ba8c9a8c2f7`; the live Gift-completed-events service runs `38f9faa8c2eee2fe24f32ed4648a28b45bc605a5`; and the live transactional-email service runs `f51d248def58a591556464797e64f8757936e735`. No Gift/email Eventarc trigger appeared in the `us-central1` or `europe-west2` trigger inventory queried. The completion-event service is tagged for delivery completion and is not, by itself, evidence for payment-created email or queue consumption. Production event owners/routes therefore need reconciliation before traffic, trigger, or payment-service changes.

No Gift/customer record, campaign participant, Stripe object, charge, refund, wallet mutation, or email was created during this audit. No live financial mutation was made.

## Surface findings

| Surface | Current evidence | Finding / severity | Action or gate |
|---|---|---|---|
| Gifts for me | Sender app and web expose one-off/monthly/four-month frequency. `gifts-payment-core.js` contains recurring-mode helpers, but the active `gifts-payment.js` Stripe Checkout construction shown by current source is hard-coded to `mode: "payment"`; no self-Gift subscription persistence or lifecycle handler was found in Gifts payment/webhook routes. | **P1 — recurring self-Gift may be a dead-end or charge once despite recurring selection.** Source trail is inconsistent; no live checkout was performed. | Trace all callers and intended product promise with owner. Keep recurring UI/payment unmodified until semantics, cancellation, renewal, failed-renewal and fulfilment are agreed. Then implement with dedicated subscription tests and webhook ownership. |
| Gifts for others | Sender flow covers recipient, occasion, address/date/budget, privacy, message and voice; server-owned `giftPaymentDrafts` and `giftRequests` rules prevent client finalization. Payment reservation binds sender, draft, amount, currency, provider ID and Roth debit. | **Source controls present; production behavior not certified against deployed service identity.** | Align Gift payment service source/image with protected `main`, then use controlled non-financial fixtures / test mode only where safely isolated. Never infer from UI or unit tests. |
| Business Gifts | Business repository lists up to 25 `giftRequests` scoped by `businessId`; UI intentionally shows operational status only and hides gift details. Existing card called “Recipient Status” counted request status strings containing “recipient,” a proxy unsupported by the data model. | **P1 — direct purchase/payment gap confirmed by product direction.** UI-only privacy correction is in separate PR #371; direct checkout not yet implemented. | Reuse existing Business account/membership authority and existing supported payment rails only after user selects card, invoice, Roth, or all. Define gift approval/fulfilment, per-business ownership and refund/reconciliation boundaries before implementation. Keep confidential content hidden absent explicit business-access policy. |
| Campaigns | Admin loads `giftCampaignParticipants` and `giftCampaignMatches`, has suggestion/review/bulk tools, rules deny client match writes, and approval creates draft requests. | **P1 — duplicate approval risk. Fixed in branch** with sorted-pair deterministic match ID, same-campaign/self/already-matched guards, transaction replay detection, and deterministic create-only draft Gift IDs. | Run protected CI and review. No campaign data was mutated. |
| Payments / Roth | Checkout reservation and Roth debit/release identities are deterministic; split finalization checks provider metadata, amount/currency and owner. Stripe webhook routes PaymentIntent success/failure and checkout expiry through canonical Gifts handlers. | **P1 — production source mismatch; live Stripe mode confirmed.** Current deployed Gift payment service has no source SHA env and uses a non-main image; no live/test payment probe made. | Do not deploy/change payment mode in this audit. Reconcile exact image/source and webhook subscriptions, validate rollback, and only use Stripe test mode with isolated fixtures after the appropriate release path is established. |
| Idempotency (“indemnity”) | Payment reservations, Roth ledger identities, deterministic email queue IDs, queue claims and Resend idempotency are present in source. Campaign approval was not idempotent before this branch change. | **Campaign mutation gap fixed in branch; production not yet fixed.** Email exactly-once is not asserted from source alone. | Protected CI, merge/deploy, then inspect durable queue/provider IDs and replay evidence. |
| Email | Current policy defines payment confirmation/problem, approval/rejection/readiness, sender delivery, and role-specific Story-ready mail. Payment-problem copy distinguishes failed vs unconfirmed. Queue/consumer source uses deterministic IDs and source/token revalidation. | **No template change made. Production route/certification incomplete.** Live email worker is at `f51d248`; queried Eventarc inventory had no queue consumer route. The active Gen 1 Gift-created/Gift-updated Firestore owners are Gift push/status publishers (9 Sep); the old `onGiftEmailNotification` consumer is OFFLINE. This does not establish delivery from `emailQueue` into Cloud Run. Template acceptance is not inbox delivery. | Reconcile all event/queue subscription owners and prove one live queue consumer before changing routes. Controlled approved-recipient certification only after route proof. Ask Jason before any new/changed template. |
| Story, privacy, voice | Secure Story tokens, role checks and privacy controls exist in source; admin Story tools include privacy and retry actions. Firestore customer access is restrictive. | **Feature/source coverage exists; production runtime and restart proof incomplete.** | Confirm Story triggers, private consumer health, native restart/recovery, and live token access without exposing private Story content. |
| Admin gaps | Earlier `HISTORICAL_ADMIN_PARITY_REPORT.md` is stale: latest main now loads match records, offers Gifts Campaign UI, and has Gift workspace actions. The Gift Drawer/workflow exists; policies deny client writes to canonical Gift/match records. | **Do not act on stale parity claims.** Remaining audit needed for deployed Admin authority identities, pagination/permission boundaries, audit trail completeness and Story media operations. | Refresh parity doc only after current live Admin and role checks are evidenced; do not restore legacy features just for parity. |

## Changes prepared on this branch

1. Campaign match approval: deterministic identity from campaign plus participant pair; reject self-match, cross-campaign match and conflicting already-matched participants; treat exact approved replay as an idempotent result; create deterministic draft-Gift IDs transactionally.
2. Business Gifts metric: remove recipient-status inference and display the privacy state instead.
3. A source-contract assertion was added for the campaign replay guards.

Local verification so far: 5 Node Admin authority/hardening contract tests passed; `flutter test test/admin_operations_test.dart` passed 56 tests; Dart formatter completed for the Business UI. These checks do not prove transaction replay behavior against Firestore, protected CI, production routing, or deployment. The audit is not complete until protected CI and deployment gates pass.

## Production evidence and unresolved gates

- Project queried: `circum-2797c`; region of current service inventory: `us-central1`.
- `circum-gift-payments-00002-clt`, 100% traffic; image tag `payment-family:84417e3b2486`; `STRIPE_MODE=live`, `STRIPE_LIVE_MODE_ENABLED=true`; no `CIRCUM_SOURCE_SHA` env was present. Secret values were not read or displayed.
- `circum-gift-completed-events-00014-cem`, 100% on `gift-final-gated`; source SHA `38f9faa8c2eee2fe24f32ed4648a28b45bc605a5`; handler kind `gift_delivery_completed`. A prior tagged `gifts-preflight` revision also exists.
- `circum-transactional-email-f51d248`, 100% traffic; image source SHA is `f51d248def58a591556464797e64f8757936e735`.
- ACTIVE Gen 1 Firestore owners observed: Gift request create and update triggers for `giftRequests/{giftId}`, and a campaign-participant update trigger. The old consumer on `giftEmailNotifications` is OFFLINE.
- Eventarc trigger lists queried in `us-central1` and `europe-west2` showed no `emailQueue` consumer route (the listed triggers were unrelated Pub/Sub schedules/recovery). Gift request create/update owners run source old enough to predate current main and their code path owns Gift status notification plus delivered-email publication; the OFFLINE legacy consumer does not prove canonical queue consumption.
- This is **not** proof no separate subscription or trigger exists elsewhere; inspect Pub/Sub subscriptions, all Eventarc locations and Cloud Run request logs before any owner switch.
- Read-only Cloud Logging query for the last 24 hours found zero `ERROR`-or-higher entries on the current serving revisions of Gift Payments (`00002-clt`), Gift Completed Events (`00014-cem`) and transactional email (`f51d248`). The Gift Completed Events service had three `ERROR`-or-higher entries on older revisions; two were HTTP 503s on revisions `00010-mil` and `00011-fug` at 12:20 UTC. No payload/customer details were read. These older-revision errors need attribution before calling the service clean.
- No queue record, Stripe event, or Resend acceptance was inspected or created in this audit.
- Full release/deploy must wait for protected CI, merge, exact event-owner/trigger reconciliation, service-specific rollback readiness, and a narrowly scoped deployment plan.

## Questions requiring product direction before further payment work

1. Should “Gift myself” monthly/four-month selections represent Stripe subscriptions that renew automatically, or scheduled one-off gifts at that frequency? Current source does not prove either complete behavior.
2. Business direct payment is approved. Which existing rails should it use: card/Stripe Checkout, Business invoices, Business Roth, or all currently supported rails? No checkout will be built until this is explicit.
3. Do you want any additional Gift emails beyond the already documented policy? I will not draft or create them until you explicitly approve which event, recipient, and purpose.

## Definition of done

- Protected CI passes and branch is merged through the repository’s normal protected path.
- Exact deployed source/image, live Stripe webhook ownership, Eventarc triggers, email queue owner, and rollback path are reconciled.
- Scoped deploy only; production revisions reach intended traffic without touching unrelated services.
- Campaign approval replay produces one match and exactly two draft Gift requests in isolated fixtures.
- Gift checkout/idempotency and retry recovery are covered without live-mode financial mutation.
- Approved-recipient email certification uses existing templates only unless Jason separately approves new copy; provider acceptance is distinguished from inbox delivery.
- Post-deploy errors/5xx, queue outcomes, admin access, Business isolation, recipient privacy and Story-link behavior are checked and reported with concrete IDs.
