# Circum transactional email surface audit

This audit is derived from canonical `b4c5978` and the customer-copy release branch. It is intentionally separate from deployment and provider certification. It records only email behavior established by source or existing policy. A surface marked “not established” is not an authorization to invent a new customer email.

## Shared transport boundary

| Field | Decision |
|---|---|
| Queue | Firestore `emailQueue` only |
| Consumer | Private authenticated Cloud Run `circum-transactional-email` via Eventarc |
| Claim | Queue-document lease plus terminal status and Resend idempotency key equal to the deterministic queue id |
| Validation | Recipient normalization/suppression and authoritative source-document revalidation before provider call |
| Provider | Resend, with `RESEND_API_KEY`, Gifts sender binding, and optional verified Business/Health+/Info bindings; values never logged |
| Marketing | Newsletter/Mailchimp remains separate and dormant; no marketing send is activated |

## Current source map

| Surface | Authoritative event/source | Recipient | Current transport/publisher | Queue event and identity | Decision |
|---|---|---|---|---|---|
| Gifts delivery | `giftRequests` reaches authoritative delivered state | Gift Sender email | `transactional-email-publishers.js` / `gift-email-notifications.js` → `emailQueue` | `gift_delivered`, `gift_{giftId}_gift_delivered` | Cloud Run transactional email |
| Gift Story | Gift Story finalization in `gift-story-automation.js` | Sender and recipient story contacts | `queueStoryEmail` → `emailQueue`; app/link notification remains separate | `gift_story_ready`, `gift_story_{giftId}_{role}` | Cloud Run transactional email |
| Health+ | `prescriptionPickups` operational status projection | Pickup email | `queueHealthNotification` → `emailQueue` | `health_{pickupId}_{type}` | Cloud Run transactional email |
| Paid booking / Gifts payment receipt | Ordinary `deliveryRequests` record created only after payment confirmation; Gifts payment receipt remains owned by Stripe | Auth-derived `senderEmail` on the canonical delivery | Cloud Run/Eventarc publisher on `deliveryRequests` create | `delivery_booking_paid`, `delivery_booking_paid_{deliveryId}` | Circum booking confirmation; never duplicates Stripe's Gifts receipt |
| Ordinary delivery completion | `deliveryRequests` reaches `delivered`/`completed` with completed settlement | Canonical `senderEmail` | Cloud Run/Eventarc publisher on `deliveryRequests` update | `delivery_completed`, `delivery_completed_{deliveryId}` | One completion email after final delivery state |
| Settled cancellations | `deliveryCancellationSettlements.status=settled` plus `deliveryRequests.cancellationSettlementStatus=settled` | Canonical sender email on delivery | Cloud Run/Eventarc publisher after settlement record update | `delivery_cancellation_settled`, `delivery_cancellation_settled_{deliveryId}` | Downstream notice only; does not alter settlement/refund/Roth logic |
| Business invoice | `businessInvoices` transitions to fully paid | Invoice `billingEmail` | Cloud Run/Eventarc publisher on invoice update | `business_invoice_paid`, `business_invoice_paid_{invoiceId}` | Only fully settled invoice; no partial-payment email |
| Roth movement | `walletTransactions.status=completed`, sender wallet | Ledger `userEmail` | Cloud Run/Eventarc publisher on ledger create | `roth_movement_completed`, `roth_movement_completed_{transactionId}` | Generic account activity notice; ledger remains authoritative |
| Referral award | Referral status `roth_awarded` and both role-specific reward ledger entries completed | Referral `referrerEmail` and `referredEmail` | Cloud Run/Eventarc publisher on referral update | `referral_award_finalized`, `referral_award_{referralId}_{role}` | No email until both ledger writes are final |
| Rider application decision | `riderProfiles.approvalStatus` transitions to approved, rejected, or more information requested through Rider authority | Canonical Rider profile email | Cloud Run/Eventarc publisher on profile update | `rider_application_decision`, `rider_application_{riderId}_{decision}_{decisionTimestamp}` | Privacy-safe status-only message; no documents/admin notes |
| Sender welcome | Authoritative Sender account initialization plus completed Starter Roth grant | Sender account email | `sender-account.js` / wallet-repair path → `sender-welcome-email.js` → `emailQueue` | `sender_welcome_ready`, `sender_welcome_{uid}` | Dedicated exactly-once welcome; never generic Roth activity |
| Auth | Firebase Authentication authority | Firebase Auth email | Firebase Auth-managed transport | Not `emailQueue` | Remains separate |
| Newsletter/marketing | Newsletter provider/audience authority | Marketing subscriber | Mailchimp/newsletter adapter, independently gated | Not `emailQueue` | Dormant; not activated |

## Customer-copy inventory

Every existing `emailQueue` publisher uses `transactional-email-templates.js`. Each rendered message contains a subject, preheader, human heading, plain-text body, HTML body with hidden preheader, support footer, and a canonical Circum CTA where one is safe.

| Internal source/state | Customer meaning | Subject / heading family | Sender |
|---|---|---|---|
| New Sender account plus completed Starter Roth grant | Account is ready and the one-time £5 Roth starter credit is available | “Welcome to CIRCUM — your account is ready” / “Welcome to CIRCUM” | `info@circumuk.com` |
| Paid ordinary delivery booking | Payment is confirmed and the booking can be followed | “Your CIRCUM delivery booking is confirmed” / “Your delivery booking is confirmed” | `info@circumuk.com` |
| Final ordinary delivery with completed settlement | Delivery has reached completion | “Your CIRCUM delivery has arrived” / “Your delivery is complete” | `info@circumuk.com` |
| Settled delivery cancellation | Cancellation and applicable payment settlement are complete | “Your CIRCUM delivery cancellation is complete” | `info@circumuk.com` |
| Business invoice fully paid | Business payment is received and the invoice is settled | “Your CIRCUM Business invoice is paid” | `business@circumuk.com` when verified, otherwise `info@circumuk.com` |
| Completed non-starter Roth ledger activity | Wallet credit, debit, refund, restoration, or update explained in plain English | “Your CIRCUM Roth wallet has been updated” | `info@circumuk.com` |
| Referral reward with both role ledgers final | Referral reward is available in Roth | “Your CIRCUM referral reward is ready” | `info@circumuk.com` |
| Rider authority decision | Approval, application update, or request for more information without admin/document detail | Decision-specific plain-English subject | `info@circumuk.com` |
| Health+ operational status or reminder | Collection, rider, prescription, delivery, exception, reschedule, or reminder update | Status-specific Health+ subject | `health@circumuk.com` when verified, otherwise `info@circumuk.com` |
| Gift delivered | Gift reached the recipient; no address is exposed | “Your CIRCUM Gift has been delivered” | `gifts@circumuk.com` |
| Gift Story ready | Private story is available through a secure link; normal priority | “Your CIRCUM Gift Story is ready” or recipient equivalent | `gifts@circumuk.com` |

Rendered customer-facing fields are rejected by automated tests if they contain snake_case, known raw event names, Firestore/Eventarc terms, source field names, or internal notification identifiers. Queue metadata may retain internal event identity for routing and audit; it is never copied into customer-facing fields.

The following lifecycle messages remain push/in-app only under current product policy: Gift submitted-for-review, Gift curation started, ordinary Rider acceptance/progress, arrival at pickup, pickup confirmation, delivery in progress, approaching drop-off, rider-side cancellation, and routine status progression. Gift payment problems are a separate consequential Gifts event with a state-safe Sender email; no Gift refund email exists in this policy.

## One-owner rule

The previous managed `onGiftEmailNotificationCreated` export consumed a separate `giftEmailNotifications` collection and was observed `OFFLINE`. It is no longer a source export and is classified as Cloud Run superseded in the production inventory. Gifts delivery now writes the canonical `emailQueue`; the Cloud Run service is the only transactional email consumer in this change. Healthy Gen 1 functions remain untouched.

## Certification boundary

Source tests prove queue construction and the consumer state machine with fixture records. Production certification must separately prove Eventarc delivery, queue claim, provider acceptance, and persisted outcome using one approved controlled recipient. Financial source operations are authoritative and must not be created or rolled back to generate an email test.
