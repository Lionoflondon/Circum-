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
  --set-secrets=RESEND_API_KEY=RESEND_API_KEY:latest,GIFTS_EMAIL_FROM=GIFTS_EMAIL_FROM:latest
```

Before production Eventarc, verify the service is READY, has 100% traffic on the new revision, returns `/health` only through an authenticated request, reports the merged source SHA, and passes the fixture certificate in `cloud-run-transactional-email.test.js`.

The production trigger is created only after that gate:

```text
gcloud eventarc triggers create circum-transactional-emailqueue-v1 \
  --project=circum-2797c --location=us-central1 \
  --event-filters=type=google.cloud.firestore.document.v1.created \
  --event-filters=database='(default)' \
  --event-filters-path-pattern="document=projects/circum-2797c/databases/(default)/documents/emailQueue/{emailId}" \
  --destination-run-service=circum-transactional-email \
  --destination-run-region=us-central1 \
  --destination-run-path=/ \
  --service-account=circum-transactional-email-eventarc@circum-2797c.iam.gserviceaccount.com
```

The trigger service account receives only the Eventarc receiver role and Cloud Run invoker on this service. The runtime service account receives only Firestore access required by the queue/source reads and secret accessor on `RESEND_API_KEY` and `GIFTS_EMAIL_FROM`; secret values are never printed or stored in source.

## Certification boundary

Fixture certification covers valid, exact duplicate, 20-way duplicate, Eventarc retry, timeout, 429, 5xx, invalid/suppressed recipient, changed source, malformed event, and worker restart. Live certification requires one user-approved controlled recipient and proves queue record → Eventarc → claim → source/recipient validation → Resend acceptance → persisted outcome. No real payment, delivery, Business, Roth, referral, or Rider mutation is permitted for certification.

Newsletter and marketing remain outside this service and remain unactivated.
