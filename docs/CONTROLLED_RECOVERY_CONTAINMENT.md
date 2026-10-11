# Controlled recovery containment

The offline checker reads a single JSON snapshot; it never calls a cloud API,
starts a service, pulls a message, reads a secret payload, or authorizes recovery.
Run `node tools/retry_containment_check.js SNAPSHOT.json`.
Exit zero means the supplied configuration satisfies the containment checks.
It never means production, capacity, payment, or device certification.

The snapshot contains `budgets` (Budget API response with a `budgets` array),
`retry` (gcloud v1 service describe JSON), `revisions` (gcloud v1 revision list),
`subscriptions` (gcloud subscription list), and `heldSubscriptionNames` (the exact
25 names from the reviewed containment baseline). Treat that baseline as trusted
input; do not regenerate it from whichever queues happen to be held now.
Use complete, fresh inventories from the same project, record capture times, and
check pagination. This offline checker does not establish provenance or freshness.

Required containment: both service-specific monthly GBP 5 caps remain ENFORCED,
retry remains manual zero, staged cost579 remains untagged at zero traffic,
all 25 named subscriptions remain present with empty push configuration, and
retry has no traffic tags. Missing inventories fail closed.

On 11 October 2026 the obsolete `rider-p555` tag was removed from the retry
service using a tag-only traffic update. Manual zero, the revision template,
latest-created revision, and revision percentages were unchanged. The old
`00019-vit` revision still receives 100% assigned traffic and has minimum one.
The checker reports this as an automatic-scaling blocker even while containment
passes. It is an audit tool, not an enforcement hook for Cloud Run mutations.

Revision configuration is immutable. Full elimination requires a reviewed route
to a proven zero-minimum revision, removal of every old traffic/tag reference,
and a subsequent review of retirement/rollback needs. Do not switch to automatic
scaling, route traffic to uncertified #579, or create a new deployment as a test.
Manual-zero traffic revisions ignore their revision minimum; tag-only revisions
have documented exceptions, so preserve the tag-free configuration.

Before 1 November 2026, review independent containment across the project:
monthly caps reset automatically, and remaining push subscriptions or enabled
maintenance jobs may resume. Before approximately 7 November, resolve retention
for the oldest retry backlog; the estimate comes from message-age metrics, not
per-message timestamps. Creating snapshots, changing retention, acknowledging,
replaying, or releasing held subscriptions is outside this change.

Recovery gates remain authenticated application health, #579 startup, current
regional CPU usage and startup headroom, supported Sender/Website real App Check
attestation and proxy forwarding, and isolated TEST certification. Mocked tests
are source evidence only. Keep #582 open until real supported-client compatibility
is demonstrated. Current Sender startup permits absent/failed web attestation;
current Website startup blocks when the key is absent. Inspect deployed artifacts
and supported older releases rather than inferring behavior from current main.

Firestore operation totals do not attribute a caller. Use existing query/caller
telemetry to establish a noisy path before changing business queries. Missing
secret-access audit entries do not prove a version unused; pinned historical
revisions, rollback plans, external consumers, and retention obligations must be
resolved before retirement. Never retrieve secret payloads for this inventory.

References:
- https://docs.cloud.google.com/run/docs/configuring/services/manual-scaling
- https://docs.cloud.google.com/run/docs/configuring/min-instances
- https://docs.cloud.google.com/run/docs/managing/revisions
- https://docs.cloud.google.com/billing/docs/how-to/budgets-spend-caps
