# Circum transactional email surface audit

This audit is derived from canonical `342db9d` and is intentionally separate from deployment and provider certification. It records only email behavior established by source or existing policy. A surface marked “not established” is not an authorization to invent a new customer email.

## Shared transport boundary

| Field | Decision |
|---|---|
| Queue | Firestore `emailQueue` only |
| Consumer | Private authenticated Cloud Run `circum-transactional-email` via Eventarc |
| Claim | Queue-document lease plus terminal status and Resend idempotency key equal to the deterministic queue id |
| Validation | Recipient normalization/suppression and authoritative source-document revalidation before provider call |
| Provider | Resend, with `RESEND_API_KEY` and `GIFTS_EMAIL_FROM` secret bindings; values never logged |
| Marketing | Newsletter/Mailchimp remains separate and dormant; no marketing send is activated |

## Current source map

| Surface | Authoritative event/source | Recipient | Current transport/publisher | Queue event and identity | Decision |
|---|---|---|---|---|---|
| Gifts delivery | `giftRequests` reaches delivered state | Gift sender email | `platform-notifications.js` → `gift-email-notifications.js` → `emailQueue` | `gift_delivered`, `gift_{giftId}_gift_delivered` | Cloud Run transactional email |
| Gift Story | Gift Story finalization in `gift-story-automation.js` | Sender and recipient story contacts | `queueStoryEmail` → `emailQueue`; app/link notification remains separate | `gift_story_ready`, `gift_story_{giftId}_{role}` | Cloud Run transactional email |
| Health+ | `prescriptionPickups` operational status projection | Pickup email | `queueHealthNotification` → `emailQueue` | `health_{pickupId}_{type}` | Cloud Run transactional email |
| Paid booking / Gifts payment receipt | Stripe payment/Checkout receipt ownership in `gifts-payment.js` | Stripe customer/receipt email | Stripe `receipt_email` / `customer_email` | None in Circum emailQueue | Stripe remains owner; no duplicate Resend email |
| Ordinary deliveries | `deliveryRequests` and platform notification state | No source-established email recipient/policy | In-app/push notification paths in `platform-notifications.js` | None | No new email publisher added |
| Settled cancellations | Cancellation/settlement authorities | No source-established email recipient/policy | In-app/push and settlement paths | None | No new email publisher added |
| Business invoice | `businessInvoices` and `billingEmail` data exist | Billing contact data exists | Payment/in-app communication paths; no emailQueue publisher | None | Not established; no invented email |
| Roth movement | Roth ledger authoritative movement state | Account email data exists | Ledger/account paths; no emailQueue publisher | None | Not established; no invented email |
| Referral award | Referral award/referral ledger authority | Account contact data exists | Referral award paths; no emailQueue publisher | None | Not established; no invented email |
| Rider application decision | Rider approval/onboarding authority | Rider contact data exists | Rider/in-app paths; no emailQueue publisher | None | Not established; no invented email |
| Auth | Firebase Authentication authority | Firebase Auth email | Firebase Auth-managed transport | Not `emailQueue` | Remains separate |
| Newsletter/marketing | Newsletter provider/audience authority | Marketing subscriber | Mailchimp/newsletter adapter, independently gated | Not `emailQueue` | Dormant; not activated |

## One-owner rule

The previous managed `onGiftEmailNotificationCreated` export consumed a separate `giftEmailNotifications` collection and was observed `OFFLINE`. It is no longer a source export and is classified as Cloud Run superseded in the production inventory. Gifts delivery now writes the canonical `emailQueue`; the Cloud Run service is the only transactional email consumer in this change. Healthy Gen 1 functions remain untouched.

## Certification boundary

Source tests prove queue construction and the consumer state machine with fixture records. Production certification must separately prove Eventarc delivery, queue claim, provider acceptance, and persisted outcome using one approved controlled recipient. Financial source operations are authoritative and must not be created or rolled back to generate an email test.
