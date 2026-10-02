# Delivery maintenance recovery

The four failed scheduled workers retain their existing Scheduler jobs, topics, subscriptions, retention and acknowledgement deadlines. Only authenticated push destinations move to existing standalone Cloud Run owners: notification retries owns activation, escalation and lifecycle maintenance; Rider availability owns stale presence. Existing Eventarc and notification retry routes stay in place.

`scheduled-delivery-core.js` and `delivery-operational-events.js` reconcile the pure policies/helpers from the downloaded deployed archives. `delivery-watchdog-policy.js` retains the deployed state predicates and threshold policy without replacing the healthy movement timeline handler. The maintenance worker reconciles its projection directly against current delivery state.

Activation commits a pending dispatch job with the scheduled transition, so a crash cannot lose dispatch. Retrying dispatch checks current delivery state transactionally and creates deterministic notification records; acceptance cannot be overwritten. Reserved Rider approval, vehicle readiness and active work are reread before reservation activation.

Escalation checkpoints and deterministic stage/recipient notification records commit together. Rider presence and eligibility are reread inside the same transaction. Watchdog incident, timeline, projection and alert records commit together only after current delivery and tracking state are checked. Stale presence rereads the latest heartbeat before changing freshness and preserves online intent, active work and financial data.

Notifications enter the existing retry authority in a known pre-send state. That authority suppresses stale delivery offers/reminders and resolved incidents, excludes disabled admins, and does not retry uncertain provider outcomes automatically. Neither maintenance nor its fixture route performs payments, settlement or direct provider sends.

## Cutover and controlled drain

The private `/maintenance/<worker>/fixture` route requires an explicitly TEST-only `giftStoryRuntimeFixtures/__codex_...` root with purpose `delivery_worker_recovery`; every collection maps underneath that root. The private `/dry-run` route only reads bounded counts. Google IAM protects both, with no public invoker binding.

Production `/maintenance/<worker>` accepts only the exact existing subscription, empty message data, `scheduled=true`, a valid message ID and a non-future publication timestamp. These are heartbeat messages, not delivery commands. Their publication time is recorded as evidence; business evaluation always uses current server time.

Each worker requires an enabled `deliveryWorkerControl/<worker>` record with a finite `maxAcknowledgements` budget. A transactional lease prevents concurrent scans; a receipt deduplicates message retries. Only a successfully completed current-state scan can acknowledge its heartbeat. Further historical ticks within the original schedule interval can be coalesced after that scan; they cannot repeat historical delivery transitions. Failed scans leave messages unacknowledged and durable jobs recoverable.

Start with five acknowledgements and a small batch, inspect message ages and business effects, then increase the allowance only on clean evidence. Preserve subscription configuration and its old push destination for rollback. Do not delete legacy scheduled Function resources: their managed topic/subscription cleanup could destroy queue state. Do not seek, purge, pull-and-ack, or create a second consumer.

After queue metrics and receipt evidence certify the drain, the operator can set `mode: "steady"` with a non-future `drainCertifiedAt` timestamp. This explicitly retires the initial acknowledgement cap so normal scheduled processing cannot later stop on an exhausted cutover budget. IAM, envelope validation, current-state leases, receipt deduplication and the original schedule intervals remain enforced. A steady mode without certification fails closed.
