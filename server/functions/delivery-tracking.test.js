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
