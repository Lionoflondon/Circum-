# Transactional email release boundary

This is the narrow deployment record for the canonical `emailQueue` consumer. It does not authorize a broad Functions deploy, a newsletter send, or a financial test mutation.

## Build and deploy scope

Use the merged source SHA as both the image tag and `CIRCUM_SOURCE_SHA`:

```text
gcloud builds submit server/functions \
  --project=circum-2797c \
  --config=server/functions/cloudbuild.transactional-email.yaml \
  --substitutions=_CIRCUM_SOURCE_SHA=<MERGED_SHA>,_IMAGE=gcr.io/circum-2797c/circum-transactional-email:<MERGED_SHA>

gcloud run deploy circum-transactional-email \
  --project=circum-2797c --region=us-central1 \
  --image=gcr.io/circum-2797c/circum-transactional-email:<MERGED_SHA> \
  --service-account=circum-transactional-email@circum-2797c.iam.gserviceaccount.com \
  --no-allow-unauthenticated --ingress=internal \
  --port=8080 --concurrency=8 --timeout=60s --max=3 --min=0 \
  --set-secrets=RESEND_API_KEY=RESEND_API_KEY:latest,GIFTS_EMAIL_FROM=GIFTS_EMAIL_FROM:latest,BUSINESS_EMAIL_FROM=BUSINESS_EMAIL_FROM:latest,HEALTH_EMAIL_FROM=HEALTH_EMAIL_FROM:latest,INFO_EMAIL_FROM=INFO_EMAIL_FROM:latest
```

The queue record carries an explicit sender category. The consumer resolves
that category to the corresponding verified sender identity: Gifts →
`gifts@circumuk.com`, Business → `business@circumuk.com`, Health+ →
`health@circumuk.com`, and general Circum activity → `info@circumuk.com`.
Legacy queue records without the category are inferred from their event type,
with general activity defaulting to `info@circumuk.com`; they no longer fall
back to the Gifts identity.

Before production Eventarc, verify the service is READY, has 100% traffic on the new revision, returns `/health` only through an authenticated request, reports the merged source SHA, and passes the fixture certificate in `cloud-run-transactional-email.test.js`.

The production queue trigger is created only after the consumer fixture gate. Publisher source triggers below are created only after the publisher PR is merged and the new consumer revision is ready. All triggers target the same service and the same `emailQueue`; there is still exactly one sender.

```text
gcloud eventarc triggers create circum-transactional-emailqueue-v1 \
  --project=circum-2797c --location=nam5 \
  --event-filters=type=google.cloud.firestore.document.v1.created \
  --event-filters=database='(default)' \
  --event-filters-path-pattern="document=emailQueue/{emailId}" \
  --event-data-content-type=application/protobuf \
  --destination-run-service=circum-transactional-email \
  --destination-run-region=us-central1 \
  --destination-run-path=/ \
  --service-account=circum-tx-email-events@circum-2797c.iam.gserviceaccount.com
```

The merged publisher implementation requires these additional exact Firestore source filters, all in Eventarc location `nam5`, using event type `google.cloud.firestore.document.v1.created` or `.updated` as indicated, database `(default)`, destination service `circum-transactional-email` in `us-central1`, path `/`, and the same Eventarc service account:

Set `--event-data-content-type=application/protobuf` on every Firestore trigger, including the source triggers below.

| Event type | Document filter | Trigger name |
|---|---|---|
| created | `deliveryRequests/{deliveryId}` | `circum-tx-email-delivery-created-v1` |
| updated | `deliveryRequests/{deliveryId}` | `circum-tx-email-delivery-updated-v1` |
| updated | `deliveryCancellationSettlements/{deliveryId}` | `circum-tx-email-cancellation-updated-v1` |
| updated | `businessInvoices/{invoiceId}` | `circum-tx-email-business-invoice-updated-v1` |
| created | `walletTransactions/{transactionId}` | `circum-tx-email-wallet-created-v1` |
| updated | `referrals/{referralId}` | `circum-tx-email-referral-updated-v1` |
| updated | `riderProfiles/{riderId}` | `circum-tx-email-rider-decision-updated-v1` |
| updated | `prescriptionPickups/{pickupId}` | `circum-tx-email-healthplus-updated-v1` |
| updated | `giftRequests/{giftId}` | `circum-tx-email-gift-updated-v1` |

Do not deploy the failed Gen 1 email-publisher revisions alongside these source triggers. The existing scheduled reminder job remains unchanged; its reminders retain their existing queue identity.

The trigger service account receives only the Eventarc receiver role and Cloud Run invoker on this service. The runtime service account receives only Firestore access required by the queue/source reads and secret accessor on `RESEND_API_KEY`, `GIFTS_EMAIL_FROM`, `BUSINESS_EMAIL_FROM`, `HEALTH_EMAIL_FROM`, and `INFO_EMAIL_FROM`; secret values are never printed or stored in source.

## Certification boundary

Fixture certification covers valid, exact duplicate, 20-way duplicate, Eventarc retry, timeout, 429, 5xx, invalid/suppressed recipient, changed source, malformed event, and worker restart. Live certification requires one user-approved controlled recipient and proves queue record → Eventarc → claim → source/recipient validation → Resend acceptance → persisted outcome. No real payment, delivery, Business, Roth, referral, or Rider mutation is permitted for certification.

Newsletter and marketing remain outside this service and remain unactivated.
