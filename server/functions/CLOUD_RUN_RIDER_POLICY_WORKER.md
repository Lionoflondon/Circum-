# Rider policy worker

`circum-rider-policy-worker` is a private Node 22 Cloud Run transport for the
certified Rider operational-state transaction. It accepts only `riderId`,
`cause`, and `correlationId`, then reads authoritative Firestore state and calls
the existing `applyRiderOperationalState` implementation.

The service must remain private. Production callers are not wired by this
change. The deleted Gen 1 availability triggers must remain absent.

## Defensive reconciliation design

A future authenticated scheduler may call a separate bounded reconciliation
operation every 10 minutes. The operation must query an indexed work queue or a
bounded set of Rider IDs marked by backend mutations; it must never scan every
Rider continuously. Each Rider is passed through the same worker and semantic
no-op transaction. Retry count and task age must be bounded. Creating the
scheduler and wiring mutation sources require separate production approval.

Recommended initial Cloud Run limits are zero minimum instances, three maximum
instances, concurrency 10, and a 60-second timeout. Correctness does not depend
on those limits.
