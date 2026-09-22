# Gifts email notifications

Gifts sends two kinds of essential service email:

- Stripe sends the payment receipt to the authenticated Sender email address for every card payment, including Checkout and native PaymentIntent flows. For split payments, Stripe's receipt covers the Stripe-funded remainder; Roth-only Gifts do not create a Stripe payment or receipt.
- Circum sends one delivery confirmation when a Gift reaches `delivered`.

Delivery confirmation is created in the durable `giftEmailNotifications` outbox with a deterministic Gift/event identity. The outbox is private, prevents duplicate delivery emails, and retries transient provider failures. It never includes the delivery address or private Gift Story content in the email.

## Provider configuration

The delivery email worker uses Resend:

1. Verify the sending domain in Resend.
2. Store the API key in Secret Manager as `RESEND_API_KEY`.
3. Store the verified sender, for example `Circum Gifts <gifts@circumuk.com>`, as `GIFTS_EMAIL_FROM`.
4. Deploy only the Gifts notification/payment code and the private
   `circum-transactional-email` Cloud Run consumer. Its Firestore Eventarc
   trigger owns `giftEmailNotifications/{notificationId}` after the legacy
   managed-Functions export is retired from source.

These emails are transactional service messages, not marketing. They must not be suppressed by newsletter preferences.

## Runtime ownership

The consumer runs on Node 22 in a Debian Bookworm-slim image and accepts only
authenticated Firestore Eventarc delivery. The Cloud Run runtime service
account is separate from the Eventarc delivery identity. It has Firestore
access required for the outbox, source Gift revalidation, and durable claims,
plus read-only access to the two email secrets. Secret values are never baked
into the image or written to logs.

The old `onGiftEmailNotificationCreated` Gen 1 export remains only as a
deployed historical record until retirement is separately approved; it is
OFFLINE and is not an event owner. The Cloud Run service is the sole active
owner after its fixture, readiness, and Eventarc-routing checks pass.
