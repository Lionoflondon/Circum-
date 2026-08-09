# CIRCUM enterprise recovery runbook

This runbook records recovery entry points. It does not authorize destructive
automation or direct production data mutation.

## Deployment failure

1. Stop the affected workflow and preserve its run ID, commit, and logs.
2. Compare the live Function revision or Hosting surface manifest with the last
   certified release SHA.
3. Redeploy the last certified SHA through the normal guarded workflow.
4. Re-run the affected read-only smoke and record the rollback in Admin audit.

## Payment or finalisation failure

Use Stripe event/session lookup, payment-finalisation logs, the immutable quote
snapshot, and the delivery operational timeline. Retry only the canonical
idempotent finaliser. Never create a second charge or manufacture a delivery.

## Notification failure

Use the existing notification correlation ID and delivery timeline. Existing
retry processing must reuse the deterministic notification identity. Operators
must not create a duplicate notification document to force delivery.

## Stuck delivery

Use `deliveryOperationalState`, `operationalIncidents`, the watchdog, and the
Admin Operations Centre. Acknowledge the incident, use the supported recovery
action for the first failed transition, and retain the incident and timeline
record after resolution.

## Accidental Admin action

Preserve `adminAuditLogs`, `businessAuditLogs`, and the relevant immutable
delivery timeline. Use a domain-owned compensating operation. Do not delete the
audit record or directly rewrite a terminal lifecycle state.

## Data recovery and retention

Firestore backups, point-in-time recovery, and retention settings must be
verified in the production project before relying on them. Restoration must be
tested in a non-production project and must preserve ownership boundaries,
financial idempotency keys, and immutable completion/payment records.
