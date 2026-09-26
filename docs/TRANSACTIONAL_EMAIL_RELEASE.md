# Transactional email release boundary

This is the narrow deployment record for the canonical `emailQueue` consumer and the authoritative Sender-account welcome publisher. It does not authorize a broad Functions deploy, a newsletter send, or a financial test mutation.

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

The queue record carries one of four explicit sender categories:

| Category | Owns | Sender rule |
|---|---|---|
| Info | Normal and scheduled delivery, general account, security, referral, Roth, Rider, and undefined notifications | `info@circumuk.com` or the approved `notifications@circumuk.com` fallback |
| Health | Health+ collection, prescription, delivery, reminder, and exception updates | Verified Health+ identity when configured; otherwise Info fallback |
| Business | Business invoice and account notices | Verified Business identity when configured; otherwise Info fallback |
| Gifts | Roth-funded Gift confirmation, Gift delivery and Gift Story messages | `Circum Gifts <gifts@circumuk.com>` only |

Gifts publishers may not emit Info, Health, or Business events. Health and
Business publishers may not use the Gifts identity. A configured identity is
accepted only from the `circumuk.com` domain, and the consumer rejects
cross-family overrides.

The queue record carries an explicit sender category. Gifts resolve only to
the configured/verified `Circum Gifts <gifts@circumuk.com>` identity. Business
and Health+ use their configured/verified category identity only when that
identity has been provisioned; otherwise both fall back to the approved
`Circum <info@circumuk.com>` identity. General account, delivery, security,
referral, Roth, and undefined activity use `info@circumuk.com` (or an
explicitly configured `notifications@circumuk.com` fallback). Ordinary and
scheduled delivery are therefore Info-family, not Gifts-family. Legacy queue
records without the category are inferred from their event type; they never
fall back to the Gifts identity. A configured identity is accepted only from
the `circumuk.com` domain, and the consumer rejects cross-family overrides.

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
| created | `giftRequests/{giftId}` | `circum-tx-email-gift-created-v1` |
| updated | `giftPaymentDrafts/{giftDraftId}` | `circum-tx-email-gift-payment-problem-updated-v1` |

The Gift-created trigger is required for Roth-only and split-funded payment confirmation because finalization creates the paid Gift in one transaction. Install it only after the merged consumer revision is ready:

```text
gcloud eventarc triggers create circum-tx-email-gift-created-v1 \
  --project=circum-2797c --location=nam5 \
  --event-filters=type=google.cloud.firestore.document.v1.created \
  --event-filters=database='(default)' \
  --event-filters-path-pattern="document=giftRequests/{giftId}" \
  --event-data-content-type=application/protobuf \
  --destination-run-service=circum-transactional-email \
  --destination-run-region=us-central1 \
  --destination-run-path=/ \
  --service-account=circum-tx-email-events@circum-2797c.iam.gserviceaccount.com
```

Do not deploy the failed Gen 1 email-publisher revisions alongside these source triggers. The existing scheduled reminder job remains unchanged; its reminders retain their existing queue identity.

The trigger service account receives only the Eventarc receiver role and Cloud Run invoker on this service. The runtime service account receives only Firestore access required by the queue/source reads and secret accessor on the configured secrets. The current production deployment has verified `RESEND_API_KEY`, `GIFTS_EMAIL_FROM`, `BUSINESS_EMAIL_FROM`, `HEALTH_EMAIL_FROM`, and `INFO_EMAIL_FROM` bindings; `NOTIFICATIONS_EMAIL_FROM` remains an optional approved fallback. Secret values are never printed or stored in source.
## Sender welcome boundary

The Sender-account bootstrap and profile-update entrypoints, together with the pending-wallet repair path, call the authoritative Starter Roth grant first. Only after the grant is marked `granted` does the account path create `sender_welcome_{uid}` in `emailQueue`. The queue identity is create-only and is revalidated against `users/{uid}` plus the exact Starter Roth transaction before Resend. A wallet transaction replay for the Starter Roth grant is explicitly ignored by the generic Roth publisher, so one account cannot receive both a welcome and a generic Roth activity email.

Account creation and the Starter Roth grant do not depend on the email provider. Missing, invalid, or suppressed email is recorded as a terminal queue/user state; queue-write failure records `welcomeEmailStatus=pending` for bootstrap repair. The retry path reuses the same queue identity and never creates another financial grant.

The exact changed publisher owner is the existing `circum-account-bootstrap` Cloud Run service (plus its existing compatibility facade if the release system requires the facade source update). Deploy this owner only alongside `circum-transactional-email`; do not broad-deploy Functions or migrate healthy Gen 1 exports.

## Corrective welcome send

After protected merge, the new account-bootstrap and transactional-email revisions are fixture-certified, and live queue → claim → Resend persistence is healthy, use the authoritative existing Sender account for the explicitly authorized corrective send. Resolve the account by protected operator procedure, verify `starterRothGrantStatus=granted` and the existing `starterRothTransactionId`, and create only `sender_welcome_{uid}` with the new template. Do not create an account, write a ledger transaction, change balance, or reuse the old Roth activity queue identity. Repeating the operator action must return a create-only duplicate/no-op. Record only privacy-safe queue ID suffix, status, provider acceptance ID if policy permits, and the unchanged Roth transaction/balance evidence.
## Certification boundary

Fixture certification covers valid, exact duplicate, 20-way duplicate, Eventarc retry, timeout, 429, 5xx, invalid/suppressed recipient, changed source, malformed event, and worker restart. Live certification requires one user-approved controlled recipient and proves queue record → Eventarc → claim → source/recipient validation → Resend acceptance → persisted outcome. No real payment, delivery, Business, Roth, referral, or Rider mutation is permitted for certification.

Newsletter and marketing remain outside this service and remain unactivated.
