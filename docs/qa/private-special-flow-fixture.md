# Private special-flow provider fixture

This extension exercises the canonical Health+ booking/checkout and Business
invoice checkout handlers with an injected private Firestore namespace. It does
not change the named production Health+ or Business function revisions. Deployment
is limited to `qaSpecialFlowFixture` and `expireQaSpecialFlowFixtures`.

The callable requires App Check, Auth, TEST configuration and a UID present in
both the Sender and operator allowlists. One immutable fixture identity is allowed
per operator. The fixed unpaid Business invoice is £5; Health+ uses server route
and weight pricing. No real wallet is read or mutated. This phase uses card-only
checkout, not a mixed-funding or capture certification.

Provider objects are real TEST Checkout sessions when deployed. IDs and amounts
come from Stripe, never a client setter. Routing metadata is replaced with a
private QA discriminator (including removal of the Health+ feature fallback),
so public webhooks cannot project these sessions into production collections.
No checkout URL, client secret, private address or email is returned to callers.
The provider adapter forbids subscriptions, LIVE credentials, non-integer minor
units, foreign objects and amounts above £100. It offers no capture operation.

A persisted creation reservation precedes each provider call. Response loss is
recovered using the same Stripe idempotency key. After 23 hours an unresolved
creation fails closed for explicit reconciliation, never recreation. An operation
lease prevents cleanup racing an in-flight request. The scheduled expiry job
expires verified unpaid provider sessions, terminates private Business
reservations through the canonical cancellation handler and archives only after
confirmed terminal provider state. Unexpected capture or uncertain provider
responses leave cleanup pending and logged.

This fixture does not yet certify paid delivery projections, Scheduled/Vanguard
runtime, native completion, or source-level mobile payment-return recovery.
Those boundaries must remain explicit in release reporting.
