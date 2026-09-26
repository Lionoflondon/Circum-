# QA special-flow Cloud Run certification surface

`circum-qa-special-flow` is a private Node 22 certification transport for the
existing `qa-special-flow.js` fixture handlers. It is not a customer product
owner and does not replace healthy production payment services.

The service requires Cloud Run IAM invocation plus a Firebase ID token in the
`X-Firebase-Auth` header and a valid Firebase App Check token. The allowlist is
derived at runtime from the private `CIRCUM_QA_CERTIFICATION_CREDENTIALS`
secret; ordinary Firebase users cannot select QA mode or become a fixture
participant. The runtime binds `CIRCUM_QA_STRIPE_SECRET_KEY`, never
`STRIPE_SECRET_KEY`, and uses `STRIPE_MODE=TEST` and the existing maps secret
only for canonical Health+ distance pricing.

All writes remain below `qaSpecialFlowFixtures/{fixtureId}` and carry the
synthetic QA marker. The transport has no live webhook secret, no production
Stripe endpoint, no dispatch capability, and no route to customer financial
collections. `/health` reports only service identity, source SHA and `TEST`
mode; request logs contain action/outcome/error-class metadata only.

The service is deployed with internal ingress and without the public
unauthenticated invoker binding. The existing managed QA exports remain
untouched; no broad Functions deployment is part of this surface.
