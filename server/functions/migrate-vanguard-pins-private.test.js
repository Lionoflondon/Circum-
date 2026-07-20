/* eslint-disable max-len */
"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const migration = require("./migrate-vanguard-pins-private");

test("private authority patch preserves public attempts during first migration", () => {
  const patch = migration.privateAuthorityPatch({
    deliveryId: "delivery-1",
    delivery: {
      requestId: "request-1",
      senderId: "sender-1",
      collectionPin: "123456",
      deliveryPin: "654321",
      collectionPinAttemptCount: 2,
      deliveryPinAttemptCount: 4,
      vanguardReviewRequired: true,
      vanguardLastFailedStage: "delivery",
    },
  });
  assert.equal(patch.deliveryId, "delivery-1");
  assert.equal(patch.requestId, "request-1");
  assert.equal(patch.senderId, "sender-1");
  assert.equal(patch.collectionPin, "123456");
  assert.equal(patch.deliveryPin, "654321");
  assert.equal(patch.collectionPinAttemptCount, 2);
  assert.equal(patch.deliveryPinAttemptCount, 4);
  assert.equal(patch.vanguardReviewRequired, true);
  assert.equal(patch.vanguardLastFailedStage, "delivery");
});

test("private authority patch never overwrites valid private PINs with stale public data", () => {
  const patch = migration.privateAuthorityPatch({
    deliveryId: "delivery-2",
    delivery: {
      collectionPin: "111111",
      deliveryPin: "222222",
      collectionPinAttemptCount: 5,
      deliveryPinAttemptCount: 5,
    },
    existingPrivate: {
      collectionPin: "333333",
      deliveryPin: "444444",
      collectionPinAttemptCount: 1,
      deliveryPinAttemptCount: 2,
      vanguardReviewRequired: false,
    },
  });
  assert.equal(patch.collectionPin, "333333");
  assert.equal(patch.deliveryPin, "444444");
  assert.equal(patch.collectionPinAttemptCount, 1);
  assert.equal(patch.deliveryPinAttemptCount, 2);
});

test("partial private authority is completed from public PINs", () => {
  const patch = migration.privateAuthorityPatch({
    deliveryId: "delivery-3",
    delivery: {
      collectionPin: "123456",
      deliveryPin: "654321",
      deliveryPinAttemptCount: 3,
    },
    existingPrivate: {
      collectionPin: "999999",
    },
  });
  assert.equal(patch.collectionPin, "999999");
  assert.equal(patch.deliveryPin, "654321");
  assert.equal(patch.collectionPinAttemptCount, 0);
  assert.equal(patch.deliveryPinAttemptCount, 3);
});

test("private authority patch returns null when no PIN source exists", () => {
  assert.equal(migration.privateAuthorityPatch({
    deliveryId: "delivery-4",
    delivery: {vanguardProtocolEnabled: true},
    existingPrivate: {},
  }), null);
});

test("strip patch removes public PIN secrets and review flags", () => {
  const patch = migration.stripPublicPinsPatch({
    vanguardProtection: {
      enabled: true,
      collectionPin: "123456",
      deliveryPin: "654321",
      registryVersion: 1,
    },
  });
  assert.equal(Object.prototype.hasOwnProperty.call(patch, "collectionPin"), true);
  assert.equal(Object.prototype.hasOwnProperty.call(patch, "deliveryPin"), true);
  assert.equal(Object.prototype.hasOwnProperty.call(patch, "vanguardReviewRequired"), true);
  assert.deepEqual(patch.vanguardProtection, {
    enabled: true,
    registryVersion: 1,
  });
});

test("migration activity classifier skips completed and cancelled deliveries", () => {
  assert.equal(migration.isActive({status: "requested"}), true);
  assert.equal(migration.isActive({status: "in_transit"}), true);
  assert.equal(migration.isActive({status: "completed"}), false);
  assert.equal(migration.isActive({status: "cancelled"}), false);
});
