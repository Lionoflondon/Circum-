"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {deliveryIdFromName, claimId} = require("./cloud-run-notification-events");
const {processDeliveryCreatedOnce} = require("./platform-notifications");

test("extracts only deliveryRequests document ids", () => {
  assert.equal(deliveryIdFromName("projects/p/databases/(default)/documents/deliveryRequests/d1"), "d1");
  assert.equal(deliveryIdFromName("documents/users/u1"), null);
});

test("business claim is stable per handler and delivery", () => {
  assert.equal(claimId("delivery_created", "d1"), claimId("delivery_created", "d1"));
  assert.notEqual(claimId("delivery_created", "d1"), claimId("gift_delivery_completed", "d1"));
});

test("Gen 1 delivery create path delegates to the Cloud Run durable claim", async () => {
  let received;
  let effects = 0;
  const snapshot = {id: "delivery-1", data: () => ({status: "requested"})};
  const result = await processDeliveryCreatedOnce(snapshot, "gen1-event-1", {
    db: {unused: true},
    processOnce: async (input) => {
      received = input;
      await input.run();
      return {status: "completed"};
    },
    run: async () => {
      effects += 1;
    },
  });
  assert.deepEqual(result, {status: "completed"});
  assert.equal(effects, 1);
  assert.equal(received.kind, "delivery_created");
  assert.equal(received.eventId, "gen1-event-1");
  assert.equal(received.deliveryId, "delivery-1");
});
