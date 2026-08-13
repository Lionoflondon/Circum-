/* eslint-disable max-len */
"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const deliveryTracking = require("./delivery-tracking")._private;

test("collection PIN verification patch updates backend tracking fields", () => {
  const patch = deliveryTracking.patchForTransition({
    action: "verify_collection_pin",
    nextStatus: "pickup_verified",
    riderId: "rider-1",
  });
  assert.equal(patch.status, "pickup_verified");
  assert.equal(patch.collectionPinVerified, true);
  assert.equal(patch.collectionPinVerifiedBy, "rider-1");
  assert.equal(Object.prototype.hasOwnProperty.call(patch, "deliveryPin"), false);
  assert.equal(Object.prototype.hasOwnProperty.call(patch, "collectionPin"), false);
});

test("receiver PIN verification patch delivers without exposing PIN values", () => {
  const patch = deliveryTracking.patchForTransition({
    action: "verify_receiver_pin",
    nextStatus: "delivered",
    riderId: "rider-1",
  });
  assert.equal(patch.status, "delivered");
  assert.equal(patch.deliveryPinVerified, true);
  assert.equal(patch.deliveryPinVerifiedBy, "rider-1");
  assert.equal(Object.prototype.hasOwnProperty.call(patch, "deliveryPin"), false);
  assert.equal(Object.prototype.hasOwnProperty.call(patch, "receiverPin"), false);
});

test("rider location patch preserves live GPS contract", () => {
  const patch = deliveryTracking.liveLocationPatch({
    latitude: 51.5074,
    longitude: -0.1278,
    heading: 122,
  });
  assert.equal(patch.riderLiveLocation.latitude, 51.5074);
  assert.equal(patch.riderLiveLocation.longitude, -0.1278);
  assert.equal(patch.riderLiveLocation.heading, 122);
  assert.equal(patch.riderLiveLocation.geopoint.latitude, 51.5074);
  assert.equal(patch.riderLiveLocation.geopoint.longitude, -0.1278);
  assert.equal(Object.prototype.hasOwnProperty.call(patch, "locationHistory"), false);
  assert.equal(Object.prototype.hasOwnProperty.call(patch, "riderLocation"), false);
});

test("rider live location writes are throttled for low Firestore cost", () => {
  const now = 60000;
  const previous = {
    riderLiveLocation: {
      latitude: 51.5074,
      longitude: -0.1278,
      heading: 90,
      updatedAt: now - 9000,
    },
  };
  const nearby = deliveryTracking.liveLocationPatch({
    latitude: 51.50745,
    longitude: -0.12785,
    heading: 92,
  });
  assert.equal(
      deliveryTracking.shouldWriteLiveLocation(previous, nearby, now),
      false,
  );

  const moved = deliveryTracking.liveLocationPatch({
    latitude: 51.508,
    longitude: -0.1278,
    heading: 92,
  });
  assert.equal(
      deliveryTracking.shouldWriteLiveLocation(previous, moved, now + 10000),
      true,
  );

  const stationary = deliveryTracking.liveLocationPatch({
    latitude: 51.50741,
    longitude: -0.12781,
    heading: 92,
  });
  assert.equal(
      deliveryTracking.shouldWriteLiveLocation(previous, stationary, now + 31000),
      true,
  );
});

test("live location callable validation normalizes trusted GPS fixes", () => {
  const location = deliveryTracking.validatedLiveLocation({
    latitude: 51.5074,
    longitude: -0.1278,
    accuracyMeters: 18,
    heading: 122,
    speed: 5,
    clientRecordedAt: 12345,
    backgroundCapable: true,
    queueDepth: 2,
  });
  assert.equal(location.latitude, 51.5074);
  assert.equal(location.longitude, -0.1278);
  assert.equal(location.accuracy, 18);
  assert.equal(location.gpsSignalQuality, "high");
  assert.equal(location.backgroundCapable, true);
  assert.equal(location.queueDepth, 2);
});

test("live location callable validation rejects invalid or unreliable fixes", () => {
  assert.throws(
      () => deliveryTracking.validatedLiveLocation({latitude: 200, longitude: 0, accuracyMeters: 10}),
      /valid rider location/,
  );
  assert.throws(
      () => deliveryTracking.validatedLiveLocation({latitude: 51, longitude: 0, accuracyMeters: 300}),
      /GPS accuracy/,
  );
  const mocked = deliveryTracking.validatedLiveLocation({
    latitude: 51,
    longitude: 0,
    accuracyMeters: 10,
    mocked: true,
  });
  assert.equal(mocked.mocked, true);
});

test("PIN lookup uses private Vanguard document fields only", () => {
  assert.equal(deliveryTracking.expectedPin({pickupPin: "123456"}, "verify_collection_pin"), "123456");
  assert.equal(deliveryTracking.expectedPin({
    vanguardProtection: {deliveryPin: "654321"},
  }, "verify_receiver_pin"), "654321");
  assert.equal(deliveryTracking.expectedPin({}, "verify_collection_pin"), "");
});

test("Vanguard PIN actions require private PIN authority", () => {
  assert.equal(deliveryTracking.pinAuthorityRequired(
      {vanguardProtocolEnabled: true},
      "verify_collection_pin",
  ), true);
  assert.equal(deliveryTracking.pinAuthorityRequired(
      {vanguardProtection: {enabled: true}},
      "verify_receiver_pin",
  ), true);
  assert.equal(deliveryTracking.pinAuthorityRequired(
      {vanguardProtocolEnabled: true},
      "navigate_to_pickup",
  ), false);
  assert.equal(deliveryTracking.pinAuthorityRequired(
      {},
      "verify_collection_pin",
  ), false);
});

test("public verification patches never expose or clear PIN secrets", () => {
  const collectionPatch = deliveryTracking.patchForTransition({
    action: "verify_collection_pin",
    nextStatus: "pickup_verified",
    riderId: "rider-1",
  });
  const deliveryPatch = deliveryTracking.patchForTransition({
    action: "verify_receiver_pin",
    nextStatus: "delivered",
    riderId: "rider-1",
  });
  for (const patch of [collectionPatch, deliveryPatch]) {
    assert.equal(Object.prototype.hasOwnProperty.call(patch, "collectionPin"), false);
    assert.equal(Object.prototype.hasOwnProperty.call(patch, "pickupPin"), false);
    assert.equal(Object.prototype.hasOwnProperty.call(patch, "deliveryPin"), false);
    assert.equal(Object.prototype.hasOwnProperty.call(patch, "receiverPin"), false);
    assert.equal(Object.prototype.hasOwnProperty.call(patch, "dropoffPin"), false);
    assert.equal(Object.prototype.hasOwnProperty.call(patch, "vanguardProtection"), false);
    assert.equal(Object.prototype.hasOwnProperty.call(patch, "collectionPinAttemptCount"), false);
    assert.equal(Object.prototype.hasOwnProperty.call(patch, "deliveryPinAttemptCount"), false);
  }
});

test("blocked rider account states cannot transition deliveries", () => {
  assert.throws(
      () => deliveryTracking.assertRiderOperational({accountState: "frozen"}),
      /cannot perform delivery actions/,
  );
  assert.doesNotThrow(
      () => deliveryTracking.assertRiderOperational({accountState: "approved"}),
  );
});

test("a rider cannot update another rider's delivery", () => {
  assert.throws(
      () => deliveryTracking.assertRiderOwnsDelivery(
          {riderId: "assigned-rider"},
          "different-rider",
      ),
      /Only the assigned rider/,
  );
  assert.doesNotThrow(
      () => deliveryTracking.assertRiderOwnsDelivery(
          {riderId: "assigned-rider"},
          "assigned-rider",
      ),
  );
});

test("required pickup evidence blocks incomplete verification", () => {
  assert.equal(deliveryTracking.evidenceRequirements(
      {verificationRequired: true},
      "verify_collection_pin",
      {evidenceId: "secure-ref", conditionConfirmed: true},
  ).valid, false);
  assert.equal(deliveryTracking.evidenceRequirements(
      {verificationRequired: true},
      "verify_collection_pin",
      {
        evidenceId: "secure-ref",
        conditionConfirmed: true,
        riderDeclarationAccepted: true,
      },
  ).valid, true);
});

test("settlement values reuse canonical earnings and highest trust category", () => {
  assert.deepEqual(deliveryTracking.settlementValues({
    riderEarning: 12.345,
    isScheduled: true,
    requiresVanguard: true,
  }), {amount: 12.35, deliveryAmount: 12.35, tip: 0, waiting: 0, adjustment: 0, trustPoints: 5});
  assert.equal(deliveryTracking.highestTrustAward({isHealthPlus: true, requiresVanguard: true}), 6);
  assert.equal(deliveryTracking.highestTrustAward({isGift: true, isBusiness: true}), 5);
  assert.equal(deliveryTracking.highestTrustAward({}), 1);
});

test("canonical rider rank follows backend trust thresholds", () => {
  assert.equal(deliveryTracking.canonicalRiderRankForTrust(0), "agent");
  assert.equal(deliveryTracking.canonicalRiderRankForTrust(99), "agent");
  assert.equal(deliveryTracking.canonicalRiderRankForTrust(100), "sentinel");
  assert.equal(deliveryTracking.canonicalRiderRankForTrust(300), "warden");
  assert.equal(deliveryTracking.canonicalRiderRankForTrust(700), "knight");
  assert.equal(deliveryTracking.canonicalRiderRankForTrust(1500), "veteran");
});

test("trust award patch writes backend-owned rank unless manually overridden", () => {
  const patch = deliveryTracking.riderTrustRankPatch({trustPoints: 99}, 1);
  assert.equal(patch.riderRank, "sentinel");
  assert.equal(patch.rank, "sentinel");
  assert.equal(patch.rankSource, "trust_points");

  const overridePatch = deliveryTracking.riderTrustRankPatch({
    trustPoints: 0,
    riderRank: "veteran",
    rankOverride: true,
  }, 6);
  assert.equal(Object.prototype.hasOwnProperty.call(overridePatch, "riderRank"), false);
  assert.equal(Object.prototype.hasOwnProperty.call(overridePatch, "rank"), false);
});
