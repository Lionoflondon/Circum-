/* eslint-disable max-len */
const test = require("node:test");
const assert = require("node:assert/strict");
const {
  DEFAULT_MAX_DISPATCH_RADIUS_KM,
  accountEligibilityDecision,
  dispatchEligibilityDecision,
  riderAssignedJobProjection,
  riderOfferProjection,
} = require("./rider-dispatch-authority");

const now = Date.parse("2026-08-09T12:00:00Z");
const profile = {
  approvalStatus: "approved",
  verificationStatus: "verified",
  onboardingStatus: "approved",
  dispatchEligible: true,
  documentsVerified: true,
  vehicleVerified: true,
  accountStatus: "active",
  vehicleType: "car",
};
const presence = {
  riderId: "rider-1",
  isOnline: true,
  availabilityStatus: "available",
  busy: false,
  dispatchEligible: true,
  lastHeartbeatAt: now - 1000,
  gpsStatus: "active",
  currentLocation: {
    latitude: 51.5007,
    longitude: -0.1246,
    accuracyMeters: 12,
    updatedAt: now - 1000,
  },
};
const delivery = {
  requestId: "delivery-1",
  packageDescription: "Documents",
  requiredVehicle: "car",
  workflow: "Standard",
  pickupPosition: {geopoint: {latitude: 51.501, longitude: -0.125}},
  dropoffPosition: {geopoint: {latitude: 51.51, longitude: -0.13}},
  pickupDetails: {
    fullname: "Private sender",
    phone: "+447700900000",
    address: "Pickup address",
    position: {geopoint: {latitude: 51.501, longitude: -0.125}},
  },
  dropoffDetails: {
    fullname: "Private recipient",
    phone: "+447700900001",
    address: "Drop-off address",
    position: {geopoint: {latitude: 51.51, longitude: -0.13}},
  },
  riderEarning: 6.93,
  price: 21.35,
  currency: "GBP",
  stripeCheckoutSessionId: "cs_test_private",
  paymentIntentId: "pi_private",
  fcmToken: "private-token",
  senderId: "sender-private",
  recipient: {fullName: "Private recipient"},
  internalAudit: {decision: "private"},
};

test("strict account eligibility requires every canonical approval gate", () => {
  assert.equal(accountEligibilityDecision(profile).eligible, true);
  for (const [field, value] of [
    ["approvalStatus", "pending"],
    ["verificationStatus", "pending"],
    ["onboardingStatus", "submitted"],
    ["dispatchEligible", false],
    ["documentsVerified", false],
    ["vehicleVerified", false],
  ]) {
    assert.equal(accountEligibilityDecision({...profile, [field]: value}).eligible, false, field);
  }
  assert.equal(accountEligibilityDecision({approvalStatus: "approved"}).eligible, false);
});

test("eligible Rider passes the shared dispatch predicate", () => {
  const result = dispatchEligibilityDecision({riderId: "rider-1", profile, presence, delivery, now});
  assert.equal(result.eligible, true);
  assert.ok(result.distanceKm < 1);
});

for (const [name, patch, reason] of [
  ["stale heartbeat", {lastHeartbeatAt: now - 180000}, "stale_heartbeat"],
  ["future heartbeat", {lastHeartbeatAt: now + 60000}, "stale_heartbeat"],
  ["stale GPS", {currentLocation: {...presence.currentLocation, updatedAt: now - 180000}}, "stale_or_unhealthy_location"],
  ["future GPS", {currentLocation: {...presence.currentLocation, updatedAt: now + 60000}}, "stale_or_unhealthy_location"],
  ["busy Rider", {busy: true}, "busy"],
  ["active job", {activeDeliveryId: "other-delivery"}, "active_delivery"],
  ["offline Rider", {isOnline: false}, "offline"],
  ["wrong location owner", {riderId: "rider-2"}, "location_owner_mismatch"],
]) {
  test(`${name} is rejected`, () => {
    const result = dispatchEligibilityDecision({riderId: "rider-1", profile, presence: {...presence, ...patch}, delivery, now});
    assert.equal(result.eligible, false);
    assert.equal(result.reason, reason);
  });
}

test("outside-radius Rider is rejected", () => {
  const result = dispatchEligibilityDecision({
    riderId: "rider-1",
    profile,
    presence: {...presence, currentLocation: {...presence.currentLocation, latitude: 52.0}},
    delivery,
    now,
  });
  assert.equal(result.eligible, false);
  assert.equal(result.reason, "outside_dispatch_radius");
  assert.ok(result.distanceKm > DEFAULT_MAX_DISPATCH_RADIUS_KM);
});

test("wrong vehicle and wrong service are rejected", () => {
  assert.equal(dispatchEligibilityDecision({
    riderId: "rider-1",
    profile: {...profile, vehicleType: "motorbike"},
    presence,
    delivery,
    now,
  }).reason, "vehicle_incompatible");
  assert.equal(dispatchEligibilityDecision({
    riderId: "rider-1",
    profile,
    presence,
    delivery: {...delivery, workflow: "Health+"},
    now,
  }).reason, "service_not_approved_health_plus");
  assert.equal(dispatchEligibilityDecision({
    riderId: "rider-1",
    profile: {...profile, healthDispatchEligible: true},
    presence,
    delivery: {...delivery, workflow: "Health+"},
    now,
  }).eligible, true);
});

test("a Rider who rejected or ignored an offer cannot see it again", () => {
  for (const field of ["ignoredByRiders", "rejectedByRiders"]) {
    const result = dispatchEligibilityDecision({
      riderId: "rider-1",
      profile,
      presence,
      delivery: {...delivery, [field]: ["rider-1"]},
      now,
    });
    assert.equal(result.eligible, false);
    assert.equal(result.reason, "rider_previously_declined");
  }
});

test("Rider offer is an operational allowlist with no customer payment or token data", () => {
  const offer = riderOfferProjection("delivery-1", delivery, 0.2);
  const serialized = JSON.stringify(offer);
  assert.equal(offer.price, 6.93);
  assert.equal(offer.pickupDetails.address, "Pickup address");
  assert.equal(offer.dropoffDetails.address, "Drop-off address");
  for (const secret of [
    "cs_test_private",
    "pi_private",
    "private-token",
    "Private sender",
    "Private recipient",
    "+447700900000",
    "+447700900001",
    "sender-private",
    "internalAudit",
  ]) {
    assert.equal(serialized.includes(secret), false, secret);
  }
  assert.equal("stripeCheckoutSessionId" in offer, false);
  assert.equal("recipient" in offer, false);
  assert.equal("senderId" in offer, false);
});

test("assigned and completed Rider jobs remain operational without payment metadata", () => {
  const active = riderAssignedJobProjection("delivery-1", {
    ...delivery,
    status: "accepted",
    riderId: "rider-1",
    waiting: {
      startedAt: "2026-08-09T12:10:00.000Z",
      noShowAvailableAt: "2026-08-09T12:13:00.000Z",
      customerResponded: true,
      noShowFeeAmount: 4,
      noShowRiderCompensation: 2.5,
      currency: "gbp",
      internalNote: "private waiting note",
    },
    senderDetails: {name: "Operational sender", phone: "+447700900010", email: "private@example.test"},
    receiverDetails: {name: "Operational receiver", phone: "+447700900011", email: "receiver@example.test"},
    stripeCustomerId: "cus_private",
    stripePaymentIntentId: "pi_private_assigned",
    paymentStatus: "paid",
    pricingBreakdown: {total: 21.35, stripeFee: 0.82},
    internalAudit: {reason: "private"},
  });
  const completed = riderAssignedJobProjection("delivery-1", {
    ...delivery,
    status: "completed",
    senderDetails: {name: "Historical sender", phone: "+447700900012"},
    receiverDetails: {name: "Historical receiver", phone: "+447700900013"},
    completedAt: "2026-08-09T12:00:00.000Z",
    stripePaymentIntentId: "pi_private_completed",
  }, {completed: true});

  assert.deepEqual(active.senderDetails, {name: "Operational sender", phone: "+447700900010"});
  assert.equal(active.riderId, "rider-1");
  assert.equal(active.deliveryStage, "accepted");
  assert.deepEqual(active.waiting, {
    startedAt: "2026-08-09T12:10:00.000Z",
    noShowAvailableAt: "2026-08-09T12:13:00.000Z",
    customerResponded: true,
    noShowFeeAmount: 4,
    noShowRiderCompensation: 2.5,
    currency: "GBP",
  });
  assert.equal("senderDetails" in completed, false);
  assert.equal(completed.completedAt, "2026-08-09T12:00:00.000Z");
  for (const projection of [active, completed]) {
    const serialized = JSON.stringify(projection);
    for (const privateValue of ["cus_private", "pi_private_assigned", "pi_private_completed", "private@example.test", "receiver@example.test", "pricingBreakdown", "internalAudit", "paymentStatus", "private waiting note"]) {
      assert.equal(serialized.includes(privateValue), false, privateValue);
    }
  }
});
