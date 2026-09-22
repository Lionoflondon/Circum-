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
4. Deploy only the Gifts email functions and the changed Gifts notification/payment code.

These emails are transactional service messages, not marketing. They must not be suppressed by newsletter preferences.
