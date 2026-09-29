# QA special-flow Cloud Run certification surface

`circum-qa-special-flow` is a Node 22 certification transport for the
existing `qa-special-flow.js` fixture handlers. It is not a customer product
owner and does not replace healthy production payment services.

The browser-facing edge permits Cloud Run invocation so the deployed Sender Web
can reach it, but every callable request still requires a Firebase ID token in the
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

To start a new certification cycle, the allowlisted operator calls `prepare`
with a bounded `requestId` such as `lifecycle_20260927_a`. The response returns
the new `fixtureId`; every later action, including `read` and `cleanup`, must
send that ID. Retrying the same active request is idempotent. An archived
request ID cannot be reopened; use a new one so prior audit records remain
intact. The existing one-active-fixture operator lock still applies.

The operator may use `seed_legacy_status` only on a paid QA delivery already
owned by the allowlisted Rider. It accepts exactly `rider_assigned` while the
canonical state is `accepted`, or `en_route_to_pickup` while it is
`navigating_to_pickup`. The seed is transactional and idempotent; an out-of-order
or different-owner request is rejected. It cannot change a production delivery.

The QA Rider may call `publish_location` with synthetic GPS coordinates. This
bounded adapter uses the production location validator and authoritative phase
normalizer, ignores a supplied status, and writes only a scoped QA
`activeDeliveries` projection. A delayed older coordinate cannot regress a
newer projection; terminal deliveries reject updates. This adapter verifies the
shared policy, while direct public `updateDeliveryLiveLocation` transport still
needs its own runtime probe.

The live service permits external ingress only for this browser edge; unauthenticated
or invalid-App-Check requests are rejected by the transport, and ordinary users
are rejected by the canonical QA allowlist. CORS is limited to the approved Sender
Web origins. The existing managed QA exports remain untouched; no broad Functions
deployment is part of this surface.
