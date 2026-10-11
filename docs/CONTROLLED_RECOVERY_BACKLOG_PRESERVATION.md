# Controlled recovery: backlog preservation decision

Evidence captured 11 October 2026, approximately 04:33–04:35 UTC. This is a
review plan, not authorization to operate the queues or restore production.

## Verified containment and remaining gates

Both project/service GBP 5 monthly caps are ENFORCED. Retry remains manual zero,
tag-free, with old `00019-vit` assigned 100% and staged `cost579-20261009` at zero.
All exact 25 subscriptions from the reviewed hold baseline have empty pushConfig.
The offline containment checker passes, and its 14 safety tests pass locally.
Its result explicitly refuses restoration certification.

The old retry route still has immutable min=1, max=2, CPU=1. Across the complete
us-central1 service/revision lists, it is the only minimum-positive traffic route
found. Automatic scaling would rearm that route; keep manual zero. Do not cut
over to #579 without successful application startup/dependency evidence. No
revision, percentage, scheduler or cloud setting was changed in this review.

Regional CPU allocation effective limit is 20,000 milli-vCPU. Latest quota
net_usage sample is zero at 04:25:22 UTC; no quota-exceeded series returned.
Neither proves present allocation or simultaneous startup capacity. The
reviewer must obtain synchronized regional usage and evaluate each intended
service CPU, instance bound and rollout overlap before any recovery. Do not
increase quota or caps to compensate for missing evidence.

All 13 bearer-authenticated health probes returned HTTP 500 around 04:34 UTC,
with 13 corresponding billing-disabled runtime entries. This supersedes the
prior Gifts success sample. Health-route diagnostics invoked no business handler.
Platform identity is not Firebase Auth/App Check or payment-provider proof.
Keep #582 unmerged until supported real Sender/Website clients prove attestation,
deployed proxy forwarding, and missing/invalid-token rejection at healthy runtime.
Rider main is `28efa68d37c39d8fe617f7934744b2e4b8ba056f`; its CI succeeded.
No Rider source change is justified by these findings.

## Retention decision required before 7 November

The retry subscription is
`eventarc-us-central1-circum-notification-retries-events-v1-sub-402`, on topic
`firebase-schedule-processNotificationRetries-us-central1` in circum-2797c.
It has 31-day retention, no subscription expiry, no push endpoint. The topic has
no configured topic retention; the snapshot list is empty. These metadata lists
do not establish whether any external archive already exists.

At the aligned metric endpoint 2026-10-11T04:33:59.255274Z, backlog is 288 and
oldest age is 315854 seconds. Estimated oldest publication is 7 October 12:49:45
UTC; estimated retention expiry is 7 November 12:49:45 UTC. Hourly ALIGN_MAX
metrics are estimates, not individual message timestamps or an exact count proof.

Google documents a maximum subscription retention of 31 days and a snapshot
lifetime of seven days minus oldest backlog age. A snapshot based on this sample
would expire around 14 October 12:49 UTC. Creation becomes unavailable when the
remaining lifetime falls below one hour, estimated around 14 October 11:49 UTC.
Do not assume creating a later snapshot resets the oldest message's lifetime.
A new subscription alone does not recover earlier publications. Increasing topic
retention must not be assumed to recover messages already outside its coverage.

### Proposed durable archive, subject to a separate scoped decision

Prefer a reviewed preservation-only reader of the original held subscription
that writes message envelopes to a restricted durable object archive and never
invokes a business handler. It must not acknowledge, seek, publish, purge or
restore push configuration. Pulling and lease changes are queue operations and
are not authorized by this code/docs-only recovery request. No reader was run.

Before execution, specify an exact destination, encryption/access policy,
retention/lifecycle, data handling, costs and payment/billing feasibility under
the existing caps. Do not reuse an application bucket simply because it exists.
Capture original message ID, publish time, ordering key, attributes and exact
payload bytes; use immutable checksummed records and an explicit manifest.
Keep receipt/ack identifiers out of the permanent archive. Deduplicate by source
subscription and message ID; redelivery and page limits must not be mistaken for
completeness. Test with synthetic envelopes offline, then obtain a bounded
preservation authorization covering pull/lease operations and archive writes.

Define a stop condition and independent completeness evidence before running:
reconcile unique records and publication ranges against synchronized metrics,
account for concurrent arrivals, and treat a count match alone as insufficient.
Keep originals unacknowledged and every queue hold intact. Any later restore or
republication is a separate reviewed recovery step with deduplication and business
side-effect safeguards. An archive is not proof of production restoration.

If pulls remain prohibited or billing prevents a durable write, escalate the
preservation decision now; documents and snapshots cannot preserve the backlog
through the retention deadline. The current state remains UNPRESERVED.

## Decision milestones and acceptance record

Recommended planning dates below are not scheduled jobs or permission to operate.
A named accountable owner must be recorded for each role; none is assigned by
this document. Keep the original source subscription held throughout.

| Target date (2026) | Accountable role to name | Required reviewable result |
| --- | --- | --- |
| 12 October | Recovery decision owner | Choose a preservation path or explicitly record the risk of retention loss; identify archive operator and independent verifier. |
| 13 October | Archive/security reviewer | Specify exact destination, existing access/encryption controls, data retention, cost feasibility under unchanged caps, and a bounded pull/lease/write authorization request. |
| 14 October | Recovery decision owner | Review snapshot eligibility only if separately authorized; the estimated 14 October cutoff is not a durable preservation solution. |
| 20 October | Archive operator and independent verifier | Target completion of any separately authorized preservation, leaving time for incomplete capture or billing blockers to be resolved. |
| 30 October | Containment reviewer | Complete cap-reset review before 1 November, including the 25 holds, manual zero, tag-free retry, staged zero traffic, and independent enabled scheduler/unheld push paths. |
| 2 November | Independent verifier | Final preservation readiness review; escalate unresolved destination, authorization, billing or completeness evidence before estimated 7 November expiry. |

For the proposed reader, approval must bound the source, destination, duration,
maximum delivered envelopes/bytes, lease behavior, permitted API methods and
stop conditions. Omit credentials and message bodies from diagnostic logs.
Require atomic immutable archive records, payload checksum verification and a
manifest mapping source/message ID to object/checksum/publication time. A
same-ID/different-bytes collision is a failure, not an overwrite. Stop on any
unexpected acknowledgement, business invocation, write failure or containment
change; report partial preservation explicitly.

Repeated pulls without acknowledgement may repeatedly return the same messages.
An empty pull or matching metric count cannot demonstrate complete coverage.
Define how redelivery starvation, concurrent arrivals and the original bounded
publication cohort will be accounted for before authorizing a reader. If an
independent verifier cannot establish coverage, label the archive PARTIAL and
retain that blocker; do not silently introduce acknowledgements or seek.

The decision record must include named owners, authorization scope, verified
storage/billing feasibility, synthetic validation evidence, original cohort
bounds, unique archived IDs, checksums, independent coverage evidence and any
exceptions. Until that record and durable contents exist, status is UNPRESERVED.
No queue operation, archive write, cap change or recurring task is authorized
by merging this documentation.

## Before 1 November cap reset

Review independent containment before the monthly reset: manual zero, no retry
tags, #579 zero traffic, the exact 25 holds, and the old min-one traffic reference.
Inventory remains 28 paused and two enabled scheduler jobs; unheld push
subscriptions are outside this baseline and may operate independently. Review
those existing paths without a blanket shutdown of healthy systems. Recheck all
regions/products as needed; this us-central1 inventory is not global proof.
No recurring task was created by this change.

## Attribution and secret retirement

Nine-day Firestore read/write metrics remain operation totals, not caller or
billed-cost attribution. Seven returned Firestore audit records are CreateIndex
administrative operations; no document/query caller evidence was found. Candidate
notification queries must not be changed based on these totals alone. Use existing
request IDs, query fingerprints and provider telemetry to prove attribution;
creating paid logs or running production queries needs a separate scoped decision.

The deployed historical Gen 1 `onGiftEmailNotificationCreated` is OFFLINE but
still configured with a Firestore create trigger on `giftEmailNotifications`, a
retry failure policy, and explicit RESEND_API_KEY version 9 / GIFTS_EMAIL_FROM
version 9 pins. Source retirement and OFFLINE status do not retire those metadata
dependencies or prove they cannot be restored. Preserve both pins until a reviewed
Function retirement/rollback decision and external-consumer inventory are complete.
No secret payload, version, credential or IAM mutation occurred.

## References

- https://docs.cloud.google.com/pubsub/docs/subscription-message-retention
- https://docs.cloud.google.com/pubsub/docs/replay-overview
- https://docs.cloud.google.com/run/docs/configuring/services/manual-scaling
- https://github.com/Lionoflondon/Circum-/pull/584
- https://github.com/Lionoflondon/Circum-/pull/582
