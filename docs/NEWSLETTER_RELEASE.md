# CIRCUM newsletter release and activation gates

## Status

The implementation is dormant by default. This document is not production,
delivery, legal-approval or recipient proof. Resend is the configured audience
provider, but no campaign or signup is active. Do not activate merely because
tests or protected CI pass.

## Approval and activation prerequisites

1. Approve and publish the amendment in `NEWSLETTER_PRIVACY_POLICY_AMENDMENT.md`,
   including retention periods, processor details and the real policy version.
2. Select/approve the marketing provider and its secret-management binding.
   The Resend audience adapter uses the dedicated `RESEND_NEWSLETTER_API_KEY`
   Secret Manager binding to create/update contacts and apply unsubscribe
   suppression. It does not send campaign email. The existing Gifts sending key
   is separate and is not reused. If the binding is absent, the adapter returns
   `pending_configuration`; no marketing email is currently sent.
3. Adapter requirements: bounded timeouts; revision-aware, idempotent audience
   updates; suppression precedence; category-specific consent checks and a fresh
   local suppression check before every send. Deliver HTTPS preference/withdrawal
   links without logging their bearer tokens. Only token hashes are persisted.
   Failed initial handoff requires a reviewed secure link-reissue/recovery path:
   the plaintext token cannot be recovered from its hash. No retry worker is
   included and `retry_required` is not automatic recovery.
4. Prove browser App Check on the public site, including signed-out withdrawal.
   Require both backend `NEWSLETTER_SIGNUP_ENABLED=true` and the actual
   `NEWSLETTER_PRIVACY_POLICY_VERSION`. Only then build the public website with
   the explicit `enable_newsletter=true` workflow input, which passes
   `--dart-define=NEWSLETTER_SIGNUP_ENABLED=true`. Without that build flag the
   homepage form/footer entry are hidden; preference/withdrawal routes remain.
5. Approve retention and enable the appropriate Firestore TTL policies. Rate
   records contain `expiresAt` (24 hours); writing that field alone does not
   enable deletion. Consent/suppression and analytics retention must follow the
   approved policy, not an invented period.

## Exact prospective release boundary

Project `circum-2797c`; service region `us-central1`. Cloud Run service
`circum-newsletter` exposes only these eight callable-compatible routes:

- `submitNewsletterSignup`
- `getNewsletterPreferences`
- `updateNewsletterPreferences`
- `unsubscribeNewsletter`
- `recordNewsletterAnalytics`
- `adminNewsletterDashboard`
- `adminSearchNewsletterSubscribers`
- `adminExportNewsletterSubscribers`

Firebase Hosting routes `/newsletter-api/**` on public and Admin hosts to that
service. The public and Admin clients obtain Firebase App Check tokens; Admin
requests additionally send a freshly verified Firebase ID token. Cloud Run
verifies both server-side before invoking the existing handlers.

The previous managed-Functions attempt used this exact selector:

```text
functions:submitNewsletterSignup,functions:getNewsletterPreferences,functions:updateNewsletterPreferences,functions:unsubscribeNewsletter,functions:recordNewsletterAnalytics,functions:adminNewsletterDashboard,functions:adminSearchNewsletterSubscribers,functions:adminExportNewsletterSubscribers
```

All eight managed Gen1 creations failed their platform health checks and remain
`OFFLINE`; do not retry them. Build `server/functions/Dockerfile.newsletter`
from the exact protected SHA and deploy only `circum-newsletter` with zero
minimum instances and three maximum instances. The service may accept
unauthenticated network ingress because application access is gated by verified
App Check (and Firebase Auth for Admin); do not bypass those checks. Health must
report the exact source SHA and `signupEnabled: false` until approval.

Separately review/publish the newsletter rule additions and the exact-SHA public
website (`hosting:public`) and Admin (`hosting:admin`) builds. Never include
`hosting:app`, Rider, Stripe/payments, dispatch, delivery or unrelated functions.
Firestore rules are a project-wide artifact: verify the complete current live
rules diff before publishing, and preserve unrelated changes.

**Do not dispatch the existing general Functions deployment workflow for this
release.** At base `7352ef43b39c54b882ac3c0e3d5b32436de266ac`, the dependency
resolver selected 170 exports due to shared admin code. That is outside scope.
The workflow also has an unrelated retired-Roth deletion step even with an
explicit function selector. Abort expanded scope; use a separately reviewed,
exact-selector path with no unrelated deletion. A successful managed Functions
build is not runtime-health proof; stop on activation failure, never mass retry.

## Storage and safety boundaries

- `newsletterSubscribers/{sha256(normalized email)}`: selected categories,
  consent/policy versions, timestamps, source, status, revision, token hash and
  provider status. `consentEvents` is append-only application history.
- `newsletterSignupRateLimits`: per-email, hashed-origin and global method
  budgets. Public calls require App Check, max three instances and 30s timeout.
  Limits bound accepted writes; rejected requests still incur execution/reads.
- `newsletterAnalyticsEvents`: event/source/timestamp only. No email, IP or
  tokens. Withdrawal/preference events are recorded with their transaction.
- Clients, including admin clients, cannot directly read or write these
  collections. Audience operations use server-resolved roles and App Check.
  Operations/super admins may export; analytics viewers may read but not export.
- Exports are active-only, 500 records per explicitly requested page, exclude
  token/consent internals and neutralize spreadsheet formula prefixes.
- No newsletter Firestore triggers, schedulers, recursive callbacks, account
  auto-enrolment, transactional-message opt-outs or production-data fixtures.
- Tokens are long-lived withdrawal credentials, not timestamp-expiring links.
  Reconsent rotates the token; stale/tampered tokens cannot change state.

## Verification before activation

Run the complete backend and Flutter suites, changed-files lint, ownership and
backend authority gates, and protected CI at the exact release SHA. Include:

```sh
firebase emulators:exec --only firestore --project demo-circum-newsletter 'node --test server/functions/firestore-newsletter-rules.test.js'
```

With an approved, minimal controlled recipient fixture, prove live normalized
signup/dedup, consent, preferences, provider handoff, withdrawal, suppression,
attempted post-withdrawal send prevention and authorized Admin visibility.
Verify responsive public rendering and unauthenticated links in real browsers.
Inspect function errors/invocation growth immediately after the smoke test.
Source tests and provider handoff alone cannot establish recipient delivery or
runtime safety. Keep the feature dormant if any activation gate is unresolved.
