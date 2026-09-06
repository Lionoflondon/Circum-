# Isolated QA lifecycle fixture

Two opt-in exports: `qaLifecycleFixture` (App Check callable) and
`expireQaLifecycleFixtures` (trusted scheduled cleanup). No normal exports change.
Enable only in circum-2797c with STRIPE_MODE=TEST, QA_LIFECYCLE_ENABLED=true and
QA_LIFECYCLE_ALLOWLIST JSON containing explicit operators, senders and riders.
Never log credentials or allowlist values. One active fixture per operator,
three fixed £20 deliveries, £3 tips, a one-hour expiry, bounded cleanup.

All records live below qaLifecycleFixtures/{fixtureId}; QA operator locks live
in qaLifecycleOperators. Existing default rules deny ordinary client access.
No collection-group triggers, real dispatch, user profiles, notification calls,
wallet roots, Connect transfers or rewards are invoked. A shadow approved QA
Rider is confined to this namespace and has dispatchEligible=false.

Payment/evidence are **simulation adapters**, not Stripe or device certification.
The configured TEST Stripe account would deliver events to the normal webhook,
so this fixture deliberately makes zero Stripe requests. Immutable qa_pi_/qa_re_
objects are persisted in the private namespace and explicitly providerSimulation.
No real Stripe object IDs or paid payout history are fabricated.

Lifecycle transitions, assignment, evidence metadata/PIN checks, rating input,
eligibility/privacy/categories/aggregation, tip identity and money, refund
reversal and FIFO allocation reuse shared validators. Namespace persistence for
ratings/tip capture/credit is a QA adapter; it is not execution of the public
submitDeliveryRating/submitDeliveryTip callable. QA-path results must never be
represented as public callable or real-provider success.

Call create as operator, book/pay as Sender, accept and canonical Rider actions
as Rider. The fixture fixes PINs to 2468 (pickup) and 8642 (handover); these are
synthetic only. There is no arbitrary set-status or document-write action.
The Sender may capture_tip and rate. Operator may refund_delivery, refund_tip
(reason duplicate_charge), allocate and cleanup. Rider read returns only the
safe rating/earning projections. All records retain backend synthetic markers.

Cancellation closes capture/lifecycle transactionally before reversal. Expiry
closes the root first, reconciles interrupted captures and archives unfinished
QA deliveries through cleanup-only cancellation. It never invents completion.
No financial or audit record is deleted. Scheduled cleanup also handles revoked
participants, using persisted server-owned scope instead of impersonated auth.
Human public-website attestation remains deferred. No Hosting, native artifacts,
rules changes or deployment of existing financial exports are part of this PR.
