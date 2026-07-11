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
  const now = 60_000;
  const previous = {
    riderLiveLocation: {
      latitude: 51.5074,
      longitude: -0.1278,
      heading: 90,
      updatedAt: now - 9_000,
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
      deliveryTracking.shouldWriteLiveLocation(previous, moved, now + 10_000),
      true,
  );

  const stationary = deliveryTracking.liveLocationPatch({
    latitude: 51.50741,
    longitude: -0.12781,
    heading: 92,
  });
  assert.equal(
      deliveryTracking.shouldWriteLiveLocation(previous, stationary, now + 31_000),
      true,
  );
});

test("PIN lookup reuses canonical and Vanguard fields", () => {
  assert.equal(deliveryTracking.expectedPin({pickupPin: "123456"}, "verify_collection_pin"), "123456");
  assert.equal(deliveryTracking.expectedPin({
    vanguardProtection: {deliveryPin: "654321"},
  }, "verify_receiver_pin"), "654321");
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
      {photoUrl: "secure-ref", conditionConfirmed: true},
  ).valid, false);
  assert.equal(deliveryTracking.evidenceRequirements(
      {verificationRequired: true},
      "verify_collection_pin",
      {
        photoUrl: "secure-ref",
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
