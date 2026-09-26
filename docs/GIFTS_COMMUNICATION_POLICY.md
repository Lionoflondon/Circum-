# CIRCUM Gifts communications policy

This policy is prospective. `gifts-communications-v1` becomes effective only at the production cutover timestamp recorded in `systemConfiguration/giftsCommunicationsPolicy`. Reconciliation uses the authoritative business-event timestamp, not a later maintenance `updatedAt`, and never backfills records before that timestamp.

| Event | In-app / push | Email | Classification |
|---|---:|---|---|
| Gift payment confirmed | Yes | Sender, when Roth funding is authoritative; card-only financial receipt remains Stripe-owned | `sender_email` / `provider_receipt` |
| Gift payment problem / action required | Yes | Sender | `sender_email` |
| Gift submitted for review | Yes | None | `push_only` |
| Gift approved | Yes | Sender | `sender_email` |
| Gift rejected / action required | Yes | Sender | `sender_email` |
| Gift curation started | Yes | None | `push_only` |
| Gift ready for delivery | Yes | Sender | `sender_email` |
| Rider and ordinary delivery progress | Yes | None | `push_only` |
| Gift delivered | Yes | Sender only | `sender_email` |
| Gift Story ready | Yes | Sender and Recipient, separate secure Story links | `sender_and_recipient_email` |
| Gift refund email | No | Not applicable; not implemented by Gifts policy | `not_applicable` |

Every email is created with a deterministic `emailQueue` identity and revalidated against the authoritative source before the single `circum-transactional-email` consumer can call Resend. Missing or invalid contacts are terminal suppression outcomes in `giftCommunicationOutcomes`; they are not retried as missing work.

The payment-problem template has two safe copy variants. A proven failed payment says that the payment could not be completed. An interrupted, action-required, or otherwise unconfirmed result says that CIRCUM could not confirm the payment. Neither variant promises a refund or asserts that the sender was or was not charged.

The bounded manual reconciler is `server/functions/gift-email-reconciliation.js`. It requires explicit start/end bounds, a page size, a maximum work limit, and the persisted policy cutover metadata. It publishes through `transactional-email-publishers.js`; it does not call Resend directly and does not create a second email owner.
