# Normal Stripe webhook on Cloud Run

This service is the transport for Circum's normal customer Stripe events. It
uses the same `stripe-webhook-core.js` processor and existing domain handlers as
the Gen 1 `StripeWebhook`. Stripe Connect remains separate.

## Routes and safety

- `GET /health` returns runtime and source version only.
- `POST /stripe/webhook` accepts JSON up to 1 MiB and verifies the exact raw
  request bytes before routing the event.
- All other paths and methods are rejected.
- The service must run as a private Cloud Run service until a separately
  approved Stripe destination cutover.

Supported routing:

| Stripe event | Existing authority handler |
| --- | --- |
| `checkout.session.completed` | Canonical checkout router for Sender, Gift, Health+, Business and Roth; Health+ membership linker |
| `checkout.session.expired` | Gift checkout expiry |
| `payment_intent.succeeded`, `payment_intent.processing`, `payment_intent.payment_failed`, `payment_intent.canceled` | Gift, tip, then Sender payment handlers |
| `charge.succeeded` | Existing payment notification |
| `charge.refunded` | Tip refund, then canonical Stripe refund sync |
| `charge.dispute.*` | Tip dispute processor |
| `customer.subscription.created`, `customer.subscription.updated`, `customer.subscription.deleted` | Health+ membership lifecycle |
| `invoice.paid`, `invoice.payment_failed` | Health+ membership lifecycle |

Other correctly signed event types receive HTTP 200 with no business mutation.
Domain handlers retain their existing Firestore event and movement identifiers,
so delivery to both transports does not create a second idempotency namespace.

## Private deployment configuration

- Region: `us-central1`
- Runtime: Node.js 22 container
- Minimum instances: 0
- Maximum instances: 3
- Concurrency: 20
- Timeout: 60 seconds
- Memory: 512 MiB
- CPU: 1
- Ingress: all, with unauthenticated invocation disabled
- Runtime identity: a dedicated service account with only
  `roles/datastore.user`, `roles/logging.logWriter`, and secret-level
  `roles/secretmanager.secretAccessor` for `STRIPE_SECRET_KEY` and
  `STRIPE_WEBHOOK_SECRET`

Secret versions are mounted as environment variables at runtime. Secret values
must never be supplied as image build arguments or committed files. The private
phase does not set or change `STRIPE_MODE`.

## Rollback and future cutover

The existing Gen 1 destination remains active throughout the private phase. A
future public cutover must be separately approved: grant invocation, add the new
Stripe destination with a minimal event list, verify a harmless signed event and
replay, observe dual delivery, then disable the old destination only after the
shared idempotency evidence is green.

Rollback removes or disables the new Stripe destination and leaves the Cloud Run
service private. The old Gen 1 destination remains available, and no database
rollback is required because both transports use the same domain identifiers.
