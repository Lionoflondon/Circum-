"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const core = require("./delivery-completed-event");

test("builds a complete canonical DeliveryCompleted payload", () => {
  const event = core.buildDeliveryCompletedEvent({
    deliveryId: "delivery-1",
    riderId: "rider-1",
    trustPoints: 4,
    delivery: {
      senderId: "sender-1",
      recipientId: "recipient-1",
      type: "business",
      businessOrderId: "order-1",
      evidenceSummary: {latestPhotoPath: "deliveries/delivery-1/evidence/photos/p.jpg", verifiedPhotoCount: 1},
      vanguardRequired: true,
    },
    completedAt: "2026-08-05T12:00:00.000Z",
  });
  assert.equal(event.eventId, "delivery_completed_delivery-1");
  assert.equal(event.eventType, "DeliveryCompleted");
  assert.equal(event.businessOrderId, "order-1");
  assert.equal(event.proofOfDeliveryPath, "deliveries/delivery-1/evidence/photos/p.jpg");
  assert.equal(event.vanguardEnabled, true);
  assert.equal(event.trustPoints, 4);
});

test("event identity is deterministic for idempotent publication", () => {
  const first = core.buildDeliveryCompletedEvent({deliveryId: "delivery-2", delivery: {}});
  const second = core.buildDeliveryCompletedEvent({deliveryId: "delivery-2", delivery: {}});
  assert.equal(first.eventId, second.eventId);
});

test("subscriber set is independently addressable", () => {
  assert.deepEqual(Object.keys(core._private.subscribers).sort(), [
    "admin", "analytics", "business", "gifts", "healthPlus", "iris",
    "legends", "notifications", "recipient", "referrals", "rider", "sender", "vanguard",
  ]);
});

test("publication uses create semantics so the event cannot be overwritten", () => {
  const calls = [];
  const transaction = {
    create(ref, event) {
      calls.push({path: ref.path, event});
    },
  };
  const event = core.buildDeliveryCompletedEvent({deliveryId: "delivery-3", delivery: {}});
  core.publishDeliveryCompleted({transaction, db: {collection: () => ({doc: (id) => ({path: id})})}, event});
  assert.equal(calls.length, 1);
  assert.equal(calls[0].path, event.eventId);
  assert.equal(calls[0].event.eventType, "DeliveryCompleted");
});

test("a duplicate subscriber delivery is skipped after the first completion", async () => {
  const docs = new Map();
  const writes = [];
  const refFor = (collection, id) => ({
    path: `${collection}/${id}`,
    async get() {
      const value = docs.get(`${collection}/${id}`);
      return {exists: Boolean(value), data: () => value};
    },
    async set(value) {
      docs.set(`${collection}/${id}`, {...(docs.get(`${collection}/${id}`) || {}), ...value});
      writes.push(`${collection}/${id}`);
    },
  });
  const db = {
    collection(collection) {
      return {doc: (id) => refFor(collection, id)};
    },
    async runTransaction(callback) {
      const transaction = {
        async get(ref) {
          return ref.get();
        },
        set(ref, value) {
          docs.set(ref.path, {...(docs.get(ref.path) || {}), ...value});
        },
      };
      return callback(transaction);
    },
  };
  const event = core.buildDeliveryCompletedEvent({deliveryId: "delivery-4", delivery: {}});
  const first = await core._private.runSubscriber(db, event, "sender", core._private.subscribers.sender);
  const second = await core._private.runSubscriber(db, event, "sender", core._private.subscribers.sender);
  assert.equal(first.skipped, false);
  assert.equal(second.skipped, true);
  assert.equal(writes.filter((path) => path === `deliveryActivity/${event.eventId}`).length, 1);
});
