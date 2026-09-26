# Gifts platform current matrix

Reconciled against canonical `main` at `9851d59b85b291c5d63402532eaa7015c31daa58` on 2026-09-26 after PRs #370 and #371 merged. This is a source/architecture matrix; it is not production certification.

| Area | State | Current evidence and implementation boundary |
|---|---|---|
| Gifts for me / Self Gift | INCOMPLETE | Client carries `selfGiftFrequency`; backend has interval helpers. Initial payment path is authoritative, but recurring series, Stripe subscription creation and renewal fulfilment were absent before this change. |
| Gift others | PRESENT / UNVERIFIED | Server-owned draft, reservation, Stripe/Roth split and idempotent finalization exist. Deployed artifact/source alignment and live controlled proof remain separate gates. |
| Campaigns | PRESENT / UNVERIFIED | Replay-safe campaign approval repair is merged in #370; scoped deployment and synthetic campaign-effect proof remain outstanding. |
| Business Gifts | INCOMPLETE | Business membership, invoice/card/Roth payment authority exists; direct Business Gift/order orchestration is not yet a canonical surface. |
| Payments | PRESENT / INCOMPLETE | One Stripe webhook owner and Gift reservation/finalization exist. Recurring initial-to-subscription handoff is now added in this branch; deployment/QA proof remains outstanding. |
| Roth | PRESENT | Existing Gift Roth reservation/debit/release and deterministic ledger identities are reused. Recurring flow rejects Roth-only initial checkout because future renewal requires a saved card. |
| Recurring / subscription | MISSING → IMPLEMENTED IN BRANCH | `giftRecurringSeries`, deterministic invoice claims, Stripe subscription creation after successful initial payment, period-end cancellation, status/portal callables and paid-invoice renewal path are added here. Protected CI and isolated Stripe test proof are still required. |
| Delivery creation | PRESENT / INCOMPLETE | Initial Gift creation and delivery-date fields exist. Renewal date mapping now preserves the original day-of-month and enters action-required for impossible dates; production delivery creation and operational acceptance remain to be certified. |
| Story | PRESENT / PROTECTED | Existing Gift Story ownership/runtime is out of scope and must not be reopened by this work. |
| Notifications / email | PRESENT / INCOMPLETE | Central queue and Gifts sender family exist. Recurring payment-problem/cancellation messages now use deterministic queue IDs; queue/provider certification remains outstanding. Renewal Gift confirmation reuses the existing Gift-created email policy. |
| Admin | PRESENT / INCOMPLETE | Admin Gift workspace and campaign actions exist. Recurring status is customer-authenticated through status/cancellation/portal callables; read-only Admin visibility and audited safe retry still need a dedicated surface review. |
| Privacy | PRESENT / INCOMPLETE | Existing recipient privacy/request semantics and merged PR #371 metric repair are present in source/branch work. Business direct Gift privacy must remain server-authoritative and must not reveal private destinations. |
| Event / queue ownership | INCOMPLETE → NARROWED IN BRANCH | Stripe subscription/invoice routing is added to the existing webhook owner; no second webhook owner is created. Existing Gift movement/Story ownership remains unchanged. Exact deployed subscription/event/queue topology still needs read-only reconciliation before activation. |
| Reconciliation | IMPLEMENTED / UNVERIFIED | A bounded 25-series/10-invoice-per-series reconciliation is wired as `reconcileGiftRecurringRenewals`; deterministic claims make a second run zero-effective for already fulfilled invoices. Live scheduled invocation and controlled failure-recovery proof remain outstanding. |

## Implementation order

1. Finish fresh protected CI for #371 and merge independently only when green.
2. Protect the recurring branch with Functions, Flutter, lint, architecture and rules checks.
3. Add emulator/fixture coverage for successful renewal, 20-way replay/concurrency, failed/ambiguous invoice, cancellation race and action-required delivery dates.
4. Reconcile deployed Stripe webhook and queue owners by exact revision/source identity.
5. Deploy only the changed payment/webhook and client surfaces after green protected checks.
6. Run marked Stripe TEST lifecycle fixtures only; no live charges, Roth debits, customer Gifts or campaign sends.

## Canonical recurring contract

- Initial payment is the existing one-time Gift payment and may use authorized Roth plus card.
- A recurring Self Gift requires explicit consent and a card-backed initial payment.
- The Stripe subscription recurring amount is the full Gift budget; Roth is never carried into renewal invoices.
- A successful `invoice.paid` creates one new Gift with identity derived from `subscription + invoice`.
- Failed, processing or ambiguous invoice state creates no Gift.
- Cancellation uses Stripe `cancel_at_period_end`; the current paid Gift remains intact.
- An impossible date pattern creates an action-required claim and no Gift.
