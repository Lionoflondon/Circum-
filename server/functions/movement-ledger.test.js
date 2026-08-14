/* eslint-disable max-len */
"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const movement = require("./movement-ledger");

const routeFacts = {
  authority: "authoritative_route",
  distanceMiles: 5,
  durationSeconds: 900,
  geography: {},
};

test("Gift binds to scheduled engine and releases competitively when ready", () => {
  const pending = movement.giftMovement("g1", {status: "procuring", senderId: "u1"});
  assert.equal(pending.serviceType, "GIFTS");
  assert.equal(pending.status, "awaiting_procurement");
  assert.equal(pending.matchingStatus, "held");
  assert.equal(pending.fulfilmentStrategy, "scheduled_delivery");

  const ready = movement.giftMovement("g1", {
    status: "packed",
    senderId: "u1",
    authoritativeRouteFacts: routeFacts,
  });
  assert.equal(ready.status, "requested");
  assert.equal(ready.matchingStatus, "available");
  assert.equal(ready.dispatchStatus, "requested");
  assert.equal(ready.fulfilmentStrategy, "scheduled_delivery");
  assert.equal(ready.assignedRiderId, null);
});

test("future Gift stays held for competitive release", () => {
  const future = movement.giftMovement("g2", {
    status: "packed",
    senderId: "u1",
    deliveryDate: "2099-08-14T12:00:00.000Z",
    authoritativeRouteFacts: routeFacts,
  });
  assert.equal(future.status, "scheduled");
  assert.equal(future.matchingStatus, "held");
  assert.equal(future.dispatchStatus, "held");
});

test("ready Gift without route pricing enters scheduled state but stays out of dispatch", () => {
  const gift = movement.giftMovement("g2a", {
    status: "packed",
    senderId: "u1",
  });
  assert.equal(gift.status, "scheduled");
  assert.equal(gift.fulfilmentStrategy, "scheduled_delivery");
  assert.equal(gift.readyForDispatch, false);
  assert.equal(gift.matchingStatus, "held");
  assert.equal(gift.dispatchStatus, "held");
  assert.equal(gift.dispatchHoldReason, "awaiting_logistics");
  assert.equal(gift.deliveryCharge, null);
  assert.equal(gift.riderEarning, 0);
  assert.equal(gift.platformShare, 0);
});

test("Health+ movement remains held until collection details are ready", () => {
  const scheduled = movement.healthMovement("h1", {status: "scheduled"});
  assert.equal(scheduled.serviceType, "HEALTH_PLUS");
  assert.equal(scheduled.status, "scheduled");
  assert.equal(scheduled.matchingStatus, "held");

  const ready = movement.healthMovement("h1", {
    status: "scheduled",
    collectionDetailsReady: true,
    authoritativeRouteFacts: routeFacts,
  });
  assert.equal(ready.status, "requested");
  assert.equal(ready.matchingStatus, "available");
  assert.equal(ready.fulfilmentStrategy, "open_dispatch");
});

test("Health+ customer charge is separate from logistics settlement", () => {
  const subscription = movement.healthMovement("h1-sub", {
    status: "scheduled",
    collectionDetailsReady: true,
    authoritativeRouteFacts: routeFacts,
    medicationValue: 2000,
    medicationWeightKg: 20,
    riderEarning: 65,
  }, {
    amount: 100,
    recurring: true,
    riderEarning: 65,
  });
  const oneOff = movement.healthMovement("h1-one", {
    status: "scheduled",
    collectionDetailsReady: true,
    authoritativeRouteFacts: routeFacts,
  }, {
    amount: 25,
    recurring: false,
  });
  assert.equal(subscription.healthPlusCharge, 100);
  assert.equal(subscription.healthPlusPaymentType, "subscription");
  assert.equal(subscription.riderSettlementAuthority, "canonical_health_plus_delivery_pricing_v1");
  assert.notEqual(subscription.riderEarning, 65);
  assert.equal(subscription.riderEarning, oneOff.riderEarning);
  assert.equal(subscription.deliveryCharge, oneOff.deliveryCharge);
  assert.equal(subscription.platformShare, oneOff.platformShare);
});

test("Health+ ready without route pricing stays held before competitive dispatch", () => {
  const health = movement.healthMovement("h1-held", {
    status: "scheduled",
    collectionDetailsReady: true,
  }, {
    amount: 100,
    recurring: true,
  });
  assert.equal(health.status, "requested");
  assert.equal(health.readyForCollection, false);
  assert.equal(health.matchingStatus, "held");
  assert.equal(health.dispatchStatus, "held");
  assert.equal(health.dispatchHoldReason, "awaiting_logistics");
  assert.equal(health.deliveryCharge, null);
  assert.equal(health.riderEarning, 0);
});

test("Health+ uses scheduled engine only when timing explicitly requires it", () => {
  const scheduledHealth = movement.healthMovement("h2", {
    status: "scheduled",
    collectionDetailsReady: true,
    useScheduledDeliveryEngine: true,
    scheduledAt: "2099-08-14T12:00:00.000Z",
    authoritativeRouteFacts: routeFacts,
  });
  assert.equal(scheduledHealth.fulfilmentStrategy, "scheduled_delivery");
  assert.equal(scheduledHealth.status, "scheduled");
  assert.equal(scheduledHealth.matchingStatus, "held");
});

test("movement delivery ids are deterministic", () => {
  assert.equal(movement.giftMovement("abc", {}).deliveryId, "gift_abc");
  assert.equal(movement.healthMovement("xyz", {}).deliveryId, "health_xyz");
});

test("specialized movement projections use canonical delivered terminal state", () => {
  assert.equal(movement.giftMovement("gift-done", {status: "completed"}).status, "delivered");
  assert.equal(movement.healthMovement("health-done", {status: "delivered"}).status, "delivered");
});

test("specialized movement carries only explicit canonical Rider settlement", () => {
  const gift = movement.giftMovement("gift-paid", {
    authoritativeRouteFacts: routeFacts,
    grossGiftBudget: 1500,
    riderPayout: 999,
  });
  const health = movement.healthMovement("health-paid", {
    riderSettlementAuthority: "canonical",
    riderEarning: 13.5,
  });
  assert.equal(gift.isGift, true);
  assert.notEqual(gift.riderEarning, 999);
  assert.equal(gift.riderSettlementAuthority, "canonical_gift_delivery_pricing_v1");
  assert.equal(gift.giftBudget, 1500);
  assert.equal(health.isHealthPlus, true);
  assert.equal(health.requiresVanguard, true);
  assert.equal(health.riderEarning, 0);
  assert.equal(health.riderSettlementAuthority, null);
});

test("terminal delivery projects completion back to its product Activity source", async () => {
  const writes = [];
  const db = {
    collection: (collection) => ({
      doc: (id) => ({
        set: async (data, options) => writes.push({collection, id, data, options}),
      }),
    }),
  };
  await movement.projectTerminalMovement(db, "gift_g1", {status: "arrived_at_dropoff"}, {
    status: "delivered",
    sourceModule: "gifts",
    giftRequestId: "g1",
    assignedRiderId: "r1",
  });
  await movement.projectTerminalMovement(db, "health_h1", {status: "arrived_at_dropoff"}, {
    status: "delivered",
    sourceModule: "health_plus",
    healthPlusPickupId: "h1",
    assignedRiderId: "r1",
  });
  assert.equal(writes.length, 2);
  assert.deepEqual(writes.map(({collection, id}) => [collection, id]), [
    ["giftRequests", "g1"],
    ["prescriptionPickups", "h1"],
  ]);
  assert.equal(writes[0].data.status, "delivered");
  assert.equal(writes[1].data.assignedDriverId, "r1");
});

test("Gift movement writes scheduled shell before asynchronous route pricing resolves", async () => {
  const writes = [];
  let resolveRoute;
  const db = {
    collection: (collection) => ({
      doc: (id) => ({
        collection,
        id,
      }),
    }),
    runTransaction: async (callback) => callback({
      set: (ref, data, options) => writes.push({
        collection: ref.collection,
        id: ref.id,
        data,
        options,
      }),
    }),
  };
  const routePromise = new Promise((resolve) => {
    resolveRoute = resolve;
  });
  const projection = movement.projectGift(db, "async-gift", {
    status: "packed",
    senderId: "u1",
    pickupCoordinates: {latitude: 51.5, longitude: -0.1},
    dropoffAddressData: {latitude: 51.6, longitude: -0.2},
  }, () => routePromise);
  await Promise.resolve();
  const firstMovement = writes.find((write) =>
    write.collection === "deliveryRequests" && write.id === "gift_async-gift");
  assert.equal(firstMovement.data.status, "scheduled");
  assert.equal(firstMovement.data.dispatchHoldReason, "awaiting_logistics");
  assert.equal(firstMovement.data.readyForDispatch, false);

  resolveRoute(routeFacts);
  assert.equal(await projection, "gift_async-gift");
  const pricedMovement = writes.filter((write) =>
    write.collection === "deliveryRequests" && write.id === "gift_async-gift").at(-1);
  assert.equal(pricedMovement.data.status, "requested");
  assert.equal(pricedMovement.data.readyForDispatch, true);
  assert.equal(pricedMovement.data.dispatchStatus, "requested");
  assert.equal(pricedMovement.data.riderSettlementAuthority, "canonical_gift_delivery_pricing_v1");
  assert.equal(pricedMovement.data.riderEarning + pricedMovement.data.platformShare, pricedMovement.data.deliveryCharge);
});

test("Health+ movement writes held shell before asynchronous logistics pricing resolves", async () => {
  const writes = [];
  let resolveRoute;
  const db = {
    collection: (collection) => ({
      doc: (id) => ({
        collection,
        id,
        get: async () => ({
          exists: collection === "healthPlusPayments",
          data: () => ({amount: 100, recurring: true}),
        }),
      }),
    }),
    runTransaction: async (callback) => callback({
      set: (ref, data, options) => writes.push({
        collection: ref.collection,
        id: ref.id,
        data,
        options,
      }),
    }),
  };
  const routePromise = new Promise((resolve) => {
    resolveRoute = resolve;
  });
  const projection = movement.projectHealth(db, "async-health", {
    status: "scheduled",
    collectionDetailsReady: true,
    pharmacyPosition: {latitude: 51.5, longitude: -0.1},
    deliveryPosition: {latitude: 51.6, longitude: -0.2},
  }, () => routePromise);
  await Promise.resolve();
  const firstMovement = writes.find((write) =>
    write.collection === "deliveryRequests" && write.id === "health_async-health");
  assert.equal(firstMovement.data.status, "requested");
  assert.equal(firstMovement.data.dispatchHoldReason, "awaiting_logistics");
  assert.equal(firstMovement.data.readyForCollection, false);

  resolveRoute(routeFacts);
  assert.equal(await projection, "health_async-health");
  const pricedMovement = writes.filter((write) =>
    write.collection === "deliveryRequests" && write.id === "health_async-health").at(-1);
  assert.equal(pricedMovement.data.matchingStatus, "available");
  assert.equal(pricedMovement.data.riderSettlementAuthority, "canonical_health_plus_delivery_pricing_v1");
  assert.equal(pricedMovement.data.riderEarning + pricedMovement.data.platformShare, pricedMovement.data.deliveryCharge);
});
