# Transactional email customer experience

This document records the customer-facing contract for the transactional email surfaces implemented in the canonical source. It does not reopen the already-certified queue, claim, Resend idempotency, Eventarc, or sender-family infrastructure.

## Implemented event and template matrix

All rows below use the centralized `emailQueue` → private Cloud Run consumer → validation → Resend path. The internal event name is routing metadata only; it is never used as customer copy.

| Internal event | Business meaning | Subject | Preheader | Heading / body summary | CTA | From family |
|---|---|---|---|---|---|---|
| `sender_welcome_ready` | A Sender account was initialized and its one-time £5 Starter Roth grant completed | Welcome to CIRCUM — your account is ready | £5 Roth has been added to help you get started. | Welcomes the Sender, explains the £5 wallet credit and Roth in plain language, and says what happens next | Explore CIRCUM | Info |
| `roth_activity_ready` | An ordinary completed Roth wallet credit, debit, refund, or restoration | Your CIRCUM Roth wallet has been updated | A Roth credit, debit, or refund has been recorded in your wallet | States the actual movement direction and amount and points to the current balance | View Roth wallet | Info |
| `delivery_booking_paid` | A paid ordinary delivery booking was created | Your CIRCUM delivery booking is confirmed | Your paid delivery booking is now in our system. | Confirms the booking and explains that progress updates follow | Open CIRCUM | Info |
| `delivery_completed` | An ordinary delivery reached its final delivered state and settlement completed | Your CIRCUM delivery has been delivered | Your delivery has reached its destination. | Confirms delivery and points to the details | Open CIRCUM | Info |
| `delivery_cancellation_settled` | An ordinary delivery cancellation was settled | Your CIRCUM delivery cancellation is confirmed | Your delivery cancellation has been processed. | Confirms processing without inventing a refund or balance change | Open CIRCUM | Info |
| `business_invoice_paid` | A CIRCUM Business invoice became fully paid | Your CIRCUM Business invoice is paid | Your invoice payment has been received. | Confirms payment and identifies the customer-facing invoice reference when available | Open CIRCUM Business | Business |
| `referral_award_finalized` | Both referral reward ledger entries completed | Your CIRCUM referral reward is ready | Your referral reward has been added to Roth. | Explains that the reward is available in Roth | Open CIRCUM | Info |
| `rider_application_decision` | A Rider application was approved, rejected, or needs more information | Decision-specific Rider subject | Decision-specific next-step preview | Privacy-safe status and next step; no internal notes or documents | Open the Rider app | Info |
| `health_plus_*` | A Health+ pickup entered an implemented operational status | Status-specific Health+ subject | Status-specific progress preview | Human descriptions for scheduled, assigned, collection travel, collected, delivery travel, delivered, rescheduled, escalated, prescription not ready, customer unavailable, and reviewed completion | Open CIRCUM | Health+ |
| `gift_delivered` | A Gifts delivery reached delivered status | Your Circum gift was delivered | Your gift has reached its recipient. | Confirms the gift recipient and optional customer-facing gift reference | Open CIRCUM Gifts | Gifts |
| `gift_story_ready` | A private Gift Story link was created for a sender or recipient | Your CIRCUM Gift Story is ready / You have received a CIRCUM Gift Story | Your private Gift Story is ready to view. | Explains the private link, its expiry policy, and how to view it | View your Gift Story | Gifts |

## Explicitly not implemented as email surfaces

The current source does not publish separate ordinary delivery accepted, in-progress, refund, or adjustment emails; it also does not publish separate tip or receipt emails. They remain out of the matrix rather than receiving invented templates. Stripe-managed Gifts receipts and Firebase Auth-managed account emails remain outside this transactional queue.

## New-Sender welcome exactly once

The authoritative account-bootstrap and pending-wallet-repair paths mark the Starter Roth grant complete before publishing the welcome. The publisher creates a sanitized Firestore queue identity equivalent to:

```text
sender_welcome:<uid>
```

The queue record is create-only. Duplicate account calls, pending-grant repair, Eventarc replay, worker restart, and provider retry all reuse that identity. The Starter Roth ledger replay is ignored by the generic Roth publisher. A missing, invalid, or suppressed recipient produces a persisted terminal no-send state; it never calls Resend. Email failure does not roll back account creation or the Roth grant.

## Corrective-send boundary

The source change provides the deterministic welcome path and the rendering contract. A corrective welcome to the previously investigated account remains a separate production decision: it may be sent only after the canonical account is confirmed active and normal, has no test/synthetic/QA marker, and has an authoritative deliverable email. The corrective queue identity must be distinct and deterministic, and the operation must not create or modify any Roth ledger record.

## Customer-copy guard

Contract tests render every implemented template and inspect subject, preheader, heading, body, CTA, and footer. After explicit removal of URLs and email addresses, the tests reject snake_case identifiers, Firestore/queue names, collection names, raw status keys, and internal prefixes. The rendered copy is required to have zero internal-string leakage.
