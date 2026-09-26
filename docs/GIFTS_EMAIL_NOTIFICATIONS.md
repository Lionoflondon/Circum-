# Gifts email notifications

Gifts sends these essential service emails:

- Stripe sends the payment receipt to the authenticated Sender email address for every card payment, including Checkout and native PaymentIntent flows. For split payments, Stripe's receipt covers the Stripe-funded remainder; Roth-only Gifts do not create a Stripe payment or receipt.
- Circum sends one Gift confirmation to the Sender for a finalized Roth-only or split-funded payment. It waits for the paid Gift record and completed Roth debit. It does not duplicate the Stripe card receipt.
- Circum sends one delivery confirmation to the Sender after authoritative Gift delivery. It uses the canonical Gifts route; the separate Story-ready messages carry the secure Sender and Recipient Story links after Story unlock.
- Circum sends separate Story-ready messages with role-specific secure links to the Sender and Recipient after Story unlock. There is no separate Recipient delivery email.

Each Circum email is created in the canonical Firestore `emailQueue` with a deterministic Gift/event identity. The queue is private, prevents duplicate logical emails, and retries transient provider failures. The consumer rechecks the source Gift, recipient and Story token before send. It never includes a delivery address, Gift value in Recipient mail, or raw private Story content.

## Provider configuration

The Gifts email worker uses Resend:

1. Verify the sending domain in Resend.
2. Store the API key in Secret Manager as `RESEND_API_KEY`.
3. Store the verified sender, for example `Circum Gifts <gifts@circumuk.com>`, as `GIFTS_EMAIL_FROM`.
4. Deploy only the changed Gifts event owner(s) and the private
   `circum-transactional-email` Cloud Run consumer. Its Firestore Eventarc
   trigger owns `emailQueue/{emailId}` after the legacy managed-Functions
   export is retired from source.
5. Add the narrow `giftRequests/{giftId}` created Eventarc trigger for Roth-funded Gift confirmation. Keep the existing updated trigger for Story unlock and delivery publication.

These emails are transactional service messages, not marketing. They must not be suppressed by newsletter preferences.

## Runtime ownership

The consumer runs on Node 22 in a Debian Bookworm-slim image and accepts only
authenticated Firestore Eventarc delivery. The Cloud Run runtime service
account is separate from the Eventarc delivery identity. It has Firestore
access required for the queue, source Gift revalidation, and durable claims,
plus read-only access to the configured email secrets. Secret values are never baked
into the image or written to logs.

The old `onGiftEmailNotificationCreated` Gen 1 export remains only as a
deployed historical record until retirement is separately approved; it is
OFFLINE and is not an event owner. The Cloud Run service is the sole active
owner after its fixture, readiness, and Eventarc-routing checks pass.
