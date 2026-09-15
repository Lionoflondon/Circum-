"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {once} = require("node:events");
const {DocumentEventData} = require("./rider-policy-firestore-event");
const {createServer, decodeEventarcPayload, deliveryIdFromName, claimId} = require("./cloud-run-notification-events");
const {processDeliveryCreatedOnce} = require("./platform-notifications");

const EVENT_TYPE = "google.cloud.firestore.document.v1.created";

function firestorePayload(deliveryId = "eventarc-delivery-1") {
  return DocumentEventData.encode({
    value: {
      name: `projects/circum-2797c/databases/(default)/documents/deliveryRequests/${deliveryId}`,
      fields: {
        requestId: {stringValue: deliveryId},
        senderId: {stringValue: "test-eventarc-sender"},
        matchingRules: {mapValue: {fields: {requiresTwoPerson: {booleanValue: true}}}},
      },
    },
  }).finish();
}

function pubsubPushBody(payload) {
  return Buffer.from(JSON.stringify({
    message: {
      data: Buffer.from(payload).toString("base64"),
      messageId: "eventarc-message-1",
      attributes: {"ce-type": EVENT_TYPE},
    },
    subscription: "projects/circum-2797c/subscriptions/eventarc-test",
  }));
}

test("extracts only deliveryRequests document ids", () => {
  assert.equal(deliveryIdFromName("projects/p/databases/(default)/documents/deliveryRequests/d1"), "d1");
  assert.equal(deliveryIdFromName("documents/users/u1"), null);
});

test("business claim is stable per handler and delivery", () => {
  assert.equal(claimId("delivery_created", "d1"), claimId("delivery_created", "d1"));
  assert.notEqual(claimId("delivery_created", "d1"), claimId("gift_delivery_completed", "d1"));
});

test("unwraps Eventarc Pub/Sub push bodies before decoding Firestore protobuf", () => {
  const decoded = decodeEventarcPayload(pubsubPushBody(firestorePayload()));
  assert.equal(decoded.documentName, "projects/circum-2797c/databases/(default)/documents/deliveryRequests/eventarc-delivery-1");
  assert.equal(decoded.after.requestId, "eventarc-delivery-1");
  assert.equal(decoded.after.senderId, "test-eventarc-sender");
  assert.equal(decoded.after.matchingRules.requiresTwoPerson, true);
});

test("accepts an Eventarc Pub/Sub request and forwards decoded delivery fields", async () => {
  let received;
  const server = createServer({
    kind: "delivery_created",
    dbFactory: () => ({unused: true}),
    processOnce: async (input) => {
      received = input;
      return {status: "completed"};
    },
  });
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  try {
    const {port} = server.address();
    const response = await fetch(`http://127.0.0.1:${port}/`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "ce-type": EVENT_TYPE,
        "ce-id": "eventarc-push-1",
      },
      body: pubsubPushBody(firestorePayload("eventarc-delivery-2")),
    });
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {ok: true, status: "completed"});
    assert.equal(received.deliveryId, "eventarc-delivery-2");
    assert.equal(received.after.matchingRules.requiresTwoPerson, true);
  } finally {
    server.close();
    await once(server, "close");
  }
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
