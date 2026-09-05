/* eslint-disable max-len */
const test = require("node:test");
const assert = require("node:assert/strict");
const policy = require("./delivery-policy-core");

const now = Date.UTC(2026, 6, 4, 12, 0, 0);
const pickup = {lat: 51.5155, lng: -0.1419};
const nearby = {lat: 51.51555, lng: -0.14185, clientRecordedAt: now};
const farAway = {lat: 51.517, lng: -0.145, clientRecordedAt: now};

test("cancellation settlement applies fees to Stripe before Roth", () => {
  assert.deepEqual(policy.cancellationSettlement({
    grossDeliveryTotal: 20, stripePaid: 13, rothPaid: 7,
    cancellationFee: 3, riderCompensation: 2, circumRetained: 1,
  }), {
    grossDeliveryTotal: 20, stripePaid: 13, rothPaid: 7,
    cancellationFee: 3, riderCompensation: 2, circumRetained: 1,
    stripeFee: 3, rothFee: 0, stripeRefund: 10, rothRestoration: 7,
    totalRefundValue: 17, allocationPolicy: "stripe_first",
  });
});

test("cancellation settlement uses Roth only after Stripe is exhausted", () => {
  const result = policy.cancellationSettlement({
    grossDeliveryTotal: 20, stripePaid: 2, rothPaid: 18,
    cancellationFee: 5, riderCompensation: 3, circumRetained: 2,
  });
  assert.equal(result.stripeRefund, 0);
  assert.equal(result.rothRestoration, 15);
  assert.equal(result.totalRefundValue, 15);
});

test("cancellation settlement rejects payment and fee drift", () => {
  assert.throws(() => policy.cancellationSettlement({
    grossDeliveryTotal: 20, stripePaid: 12, rothPaid: 7,
    cancellationFee: 3, riderCompensation: 2, circumRetained: 1,
  }), /does not reconcile/);
  assert.throws(() => policy.cancellationSettlement({
    grossDeliveryTotal: 20, stripePaid: 13, rothPaid: 7,
    cancellationFee: 3, riderCompensation: 1, circumRetained: 1,
  }), /does not reconcile/);
});

test("Stripe-only, Roth-only and mixed cancellation matrices reconcile", () => {
  const cases = [
    {stripePaid: 20, rothPaid: 0, fee: 0, stripeRefund: 20, rothRestoration: 0},
    {stripePaid: 0, rothPaid: 20, fee: 0, stripeRefund: 0, rothRestoration: 20},
    {stripePaid: 13, rothPaid: 7, fee: 0, stripeRefund: 13, rothRestoration: 7},
    {stripePaid: 13, rothPaid: 7, fee: 3, stripeRefund: 10, rothRestoration: 7},
    {stripePaid: 13, rothPaid: 7, fee: 5, stripeRefund: 8, rothRestoration: 7},
    {stripePaid: 13, rothPaid: 7, fee: 7, stripeRefund: 6, rothRestoration: 7},
    {stripePaid: 2, rothPaid: 18, fee: 7, stripeRefund: 0, rothRestoration: 13},
  ];
  for (const item of cases) {
    const riderCompensation = item.fee === 3 ? 2 : item.fee === 5 ? 3 : item.fee === 7 ? 4 : 0;
    const result = policy.cancellationSettlement({
      grossDeliveryTotal: 20,
      stripePaid: item.stripePaid,
      rothPaid: item.rothPaid,
      cancellationFee: item.fee,
      riderCompensation,
      circumRetained: item.fee - riderCompensation,
    });
    assert.equal(result.stripeRefund, item.stripeRefund);
    assert.equal(result.rothRestoration, item.rothRestoration);
    assert.equal(result.totalRefundValue, 20 - item.fee);
    assert.equal(result.riderCompensation + result.circumRetained, item.fee);
  }
});

test("cancellation policy is free before rider acceptance", () => {
  for (const state of ["requested", "pending", "unmatched", "finding_rider", "broadcasting", "available", "awaiting_rider"]) {
    const decision = policy.cancellationDecision({state, serverNow: now});
    assert.equal(decision.canCancel, true);
    assert.equal(decision.feeAmount, 0);
    assert.equal(decision.riderCompensation, 0);
    assert.equal(decision.userFacingMessage, "You can cancel this delivery at no charge.");
  }
});

test("cancellation after acceptance applies rider compensation and platform retained amount", () => {
  for (const state of ["accepted", "rider_assigned", "navigating_to_pickup", "en_route_to_pickup"]) {
    const decision = policy.cancellationDecision({state, serverNow: now});
    assert.equal(decision.canCancel, true);
    assert.equal(decision.feeAmount, 3);
    assert.equal(decision.riderCompensation, 2);
    assert.equal(decision.platformRetainedAmount, 1);
  }
});

test("arrival free wait and late no-show fees are distinct", () => {
  const arrivedAt = now - (2 * 60 * 1000);
  const freeWait = policy.cancellationDecision({
    state: "arrived_at_pickup",
    serverNow: now,
    delivery: {arrivedAt},
  });
  assert.equal(freeWait.feeAmount, 5);
  assert.equal(freeWait.riderCompensation, 3);
  assert.equal(freeWait.freeWaitExpired, false);

  const late = policy.cancellationDecision({
    state: "waiting",
    serverNow: now,
    delivery: {arrivedAt: now - (4 * 60 * 1000)},
  });
  assert.equal(late.feeAmount, 7);
  assert.equal(late.riderCompensation, 4);
  assert.equal(late.platformRetainedAmount, 3);
  assert.equal(late.noShowAvailable, true);
});

test("sender cannot self-cancel after collection starts or after delivery", () => {
  for (const state of ["collected", "navigating_to_dropoff", "arrived_at_dropoff", "pin_required"]) {
    const decision = policy.cancellationDecision({state, serverNow: now});
    assert.equal(decision.canCancel, false);
    assert.equal(decision.requiresAdminReview, true);
  }
  const delivered = policy.cancellationDecision({state: "delivered", serverNow: now});
  assert.equal(delivered.canCancel, false);
  assert.equal(delivered.userFacingMessage, "This delivery has been completed.");
  const issue = policy.cancellationDecision({state: "issue_reported", serverNow: now});
  assert.equal(issue.requiresAdminReview, true);
});

test("40m configurable arrival radius accepts valid arrival and starts backend wait timer", () => {
  const decision = policy.validateArrival({
    deliveryId: "delivery-1",
    riderId: "rider-1",
    delivery: {riderId: "rider-1", pickupLocation: pickup},
    location: nearby,
    gpsAccuracyMeters: 5,
    serverNow: now,
  });
  assert.equal(policy.DEFAULT_POLICY.defaultArrivalRadiusMeters, 40);
  assert.equal(decision.accepted, true);
  assert.equal(decision.state, "arrived_at_pickup");
  assert.equal(decision.waiting.freeWaitMinutes, 3);
  assert.equal(decision.waiting.freeWaitEndsAt, now + 180000);
  assert.equal(decision.waiting.noShowFeeAmount, 7);
  assert.equal(decision.waiting.noShowRiderCompensation, 4);
  assert.equal(decision.waiting.currency, "GBP");
});

test("rider cannot arrive outside permitted radius or as unassigned rider", () => {
  const outside = policy.validateArrival({
    deliveryId: "delivery-1",
    riderId: "rider-1",
    delivery: {riderId: "rider-1", pickupLocation: pickup},
    location: farAway,
    gpsAccuracyMeters: 5,
    serverNow: now,
  });
  assert.equal(outside.accepted, false);
  assert.equal(outside.reason, "outside_arrival_radius");

  const wrongRider = policy.validateArrival({
    deliveryId: "delivery-1",
    riderId: "rider-2",
    delivery: {riderId: "rider-1", pickupLocation: pickup},
    location: nearby,
    serverNow: now,
  });
  assert.equal(wrongRider.accepted, false);
  assert.equal(wrongRider.reason, "assigned_rider_required");
});

test("rider cannot restart waiting timer with duplicate arrival", () => {
  const decision = policy.validateArrival({
    deliveryId: "delivery-1",
    riderId: "rider-1",
    delivery: {riderId: "rider-1", pickupLocation: pickup, pickupArrivedAt: now - 1000},
    location: nearby,
    serverNow: now,
  });
  assert.equal(decision.duplicate, true);
  assert.equal(decision.reason, "arrival_already_recorded");
});

test("arrival requires a fresh accurate non-mocked device fix", () => {
  const delivery = {riderId: "rider-1", pickupLocation: pickup};
  for (const [location, accuracy, reason] of [
    [{...nearby, clientRecordedAt: now - 120001}, 5, "fresh_location_required"],
    [{...nearby, mocked: true}, 5, "mocked_location"],
    [nearby, 101, "accurate_location_required"],
  ]) {
    const decision = policy.validateArrival({
      deliveryId: "delivery-1",
      riderId: "rider-1",
      delivery,
      location,
      gpsAccuracyMeters: accuracy,
      serverNow: now,
    });
    assert.equal(decision.accepted, false);
    assert.equal(decision.reason, reason);
  }
});

test("geofence leaving pauses waiting and re-entry resumes", () => {
  const left = policy.geofenceReentryDecision({
    deliveryId: "delivery-1",
    riderId: "rider-1",
    delivery: {riderId: "rider-1", pickupLocation: pickup, waiting: {active: true}},
    location: farAway,
    gpsAccuracyMeters: 5,
    serverNow: now,
  });
  assert.equal(left.waitingPaused, true);
  assert.equal(left.leftArrivalZoneAt, now);
  assert.match(left.riderMessage, /Return to the pickup location/);

  const reentered = policy.geofenceReentryDecision({
    deliveryId: "delivery-1",
    riderId: "rider-1",
    delivery: {riderId: "rider-1", pickupLocation: pickup, waiting: {active: true, paused: true}},
    location: nearby,
    gpsAccuracyMeters: 5,
    serverNow: now + 60000,
  });
  assert.equal(reentered.waitingPaused, false);
  assert.equal(reentered.reenteredArrivalZoneAt, now + 60000);
});

test("no-show is unavailable before threshold and available only after backend wait expiry", () => {
  const before = policy.noShowDecision({
    deliveryId: "delivery-1",
    riderId: "rider-1",
    delivery: {state: "waiting", arrivedAt: now - 179000},
    serverNow: now,
  });
  assert.equal(before.allowed, false);
  assert.equal(before.reason, "free_wait_active");

  const after = policy.noShowDecision({
    deliveryId: "delivery-1",
    riderId: "rider-1",
    delivery: {state: "waiting", arrivedAt: now - 181000},
    serverNow: now,
  });
  assert.equal(after.allowed, true);
  assert.equal(after.feeAmount, 7);
  assert.equal(after.riderCompensation, 4);
});

test("financial actions are idempotent and frontend cannot alter existing fee result", () => {
  const first = policy.financialAction({
    idempotencyKey: "delivery-1:no-show",
    chargeType: "no_show_fee",
    amount: 7,
    riderCompensation: 4,
    platformRetainedAmount: 3,
    deliveryId: "delivery-1",
    riderId: "rider-1",
    actorId: "rider-1",
    actorType: "rider",
    serverNow: now,
  });
  const duplicate = policy.financialAction({
    idempotencyKey: "delivery-1:no-show",
    amount: 999,
    riderCompensation: 999,
    existingByIdempotencyKey: {"delivery-1:no-show": first},
    serverNow: now + 1000,
  });
  assert.equal(duplicate.duplicate, true);
  assert.equal(duplicate.amount, 7);
  assert.equal(duplicate.riderCompensation, 4);
});

test("customer acknowledgement hooks record controlled extensions", () => {
  const coming = policy.customerResponseDecision({
    deliveryId: "delivery-1",
    senderId: "sender-1",
    response: "I'm coming",
    serverNow: now,
  });
  assert.equal(coming.accepted, true);
  assert.equal(coming.escalationPaused, true);

  const extension = policy.customerResponseDecision({
    deliveryId: "delivery-1",
    response: "Need 2 more minutes",
    delivery: {customerWaitExtensions: 0},
    serverNow: now,
  });
  assert.equal(extension.extensionGranted, true);
  assert.equal(extension.extensionMinutes, 2);

  const abused = policy.customerResponseDecision({
    deliveryId: "delivery-1",
    response: "Need 2 more minutes",
    delivery: {customerWaitExtensions: 1},
    serverNow: now,
  });
  assert.equal(abused.extensionGranted, false);

  const blocked = policy.customerResponseDecision({
    deliveryId: "delivery-1",
    response: "Can't come out",
    serverNow: now,
  });
  assert.equal(blocked.supportPathRequired, true);
});

test("building access and unsafe location states are audited and do not auto-penalize", () => {
  const building = policy.waitingContextDecision({
    deliveryId: "delivery-1",
    riderId: "rider-1",
    type: "waiting_for_building_access",
    note: "Reception delay",
    serverNow: now,
  });
  assert.equal(building.state, "waiting_for_building_access");
  assert.equal(building.noShowPenaltyAllowed, false);
  assert.equal(building.auditEvent.type, "waiting_for_building_access");

  const unsafe = policy.waitingContextDecision({
    deliveryId: "delivery-1",
    riderId: "rider-1",
    type: "unsafe_location_reported",
    note: "Blocked access",
    serverNow: now,
  });
  assert.equal(unsafe.requiresAdminReview, true);
  assert.equal(unsafe.autoCancelAllowed, false);
});

test("evidence package includes audit-critical data and idempotency key", () => {
  const pack = policy.evidencePackage({
    deliveryId: "delivery-1",
    actorId: "sender-1",
    actorType: "sender",
    idempotencyKey: "delivery-1:cancel",
    arrivalLocation: pickup,
    delivery: {
      id: "delivery-1",
      state: "waiting",
      riderId: "rider-1",
      senderId: "sender-1",
      arrivedAt: now - 181000,
      waiting: {startedAt: now - 181000, freeWaitEndsAt: now - 1000},
      customerArrivalResponses: [{response: "im_coming"}],
    },
    policyDecision: {feeAmount: 7, riderCompensation: 4, platformRetainedAmount: 3},
    serverNow: now,
  });
  assert.equal(pack.deliveryId, "delivery-1");
  assert.equal(pack.arrivalTimestamp, now - 181000);
  assert.equal(pack.customerResponses.length, 1);
  assert.equal(pack.idempotencyKey, "delivery-1:cancel");
  assert.equal(pack.createdAt, now);
});

test("waiting context callable persists an idempotency record", () => {
  const source = require("fs").readFileSync(require("path").join(__dirname, "delivery-policy.js"), "utf8");
  assert.match(source, /exports\.reportWaitingContext/);
  assert.match(source, /idempotencyKey/);
  assert.match(source, /idempotencyRef\(deliveryId, idempotencyKey\)/);
  assert.match(source, /transaction\.set\(idemRef, result\)/);
  assert.match(source, /duplicate: true/);
});

test("server time is mandatory for financial and wait decisions", () => {
  assert.throws(() => policy.noShowDecision({delivery: {arrivedAt: now - 181000}}), /serverNow/);
  assert.throws(() => policy.financialAction({idempotencyKey: "x", amount: 1}), /serverNow/);
});

test("fraud detection creates review signals only", () => {
  const signals = policy.fraudSignals({
    stats: {
      riderNoShowCount: 7,
      riderWaitingCompensationCount: 6,
      senderLateCancellationCount: 5,
      failedGpsValidationCount: 4,
    },
  });
  assert.ok(signals.length >= 4);
  assert.equal(signals.every((signal) => signal.automaticPenalty === false), true);
});


test("stale state aliases cannot authorize cancellation after collection", () => {
  for (const status of ["collected", "pickup_verified", "in_transit", "delivered", "cancelled_by_sender"]) {
    assert.equal(policy.cancellationDecision({state: "accepted", delivery: {state: "accepted", status}, serverNow: now}).canCancel, false);
  }
});
test("invalid monetary authority is rejected rather than coerced to zero", () => {
  for (const grossDeliveryTotal of [undefined, null, NaN, Infinity, "20"]) {
    assert.throws(() => policy.cancellationSettlement({grossDeliveryTotal, stripePaid: 13, rothPaid: 7, cancellationFee: 3}), /finite/);
  }
});


test("penny-level allocations conserve value across small contributions and all fee boundaries", () => {
  for (let stripePence = 0; stripePence <= 25; stripePence++) {
    for (let rothPence = 0; rothPence <= 25; rothPence++) {
      for (let feePence = 0; feePence <= stripePence + rothPence; feePence++) {
        const result = policy.cancellationSettlement({grossDeliveryTotal: (stripePence + rothPence) / 100,
          stripePaid: stripePence / 100, rothPaid: rothPence / 100, cancellationFee: feePence / 100});
        assert.equal(Math.round(result.stripeRefund * 100), Math.max(0, stripePence - feePence));
        assert.equal(Math.round(result.rothRestoration * 100), rothPence - Math.max(0, feePence - stripePence));
        assert.equal(Math.round(result.totalRefundValue * 100), stripePence + rothPence - feePence);
      }
    }
  }
});
