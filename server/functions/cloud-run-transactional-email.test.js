"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {once} = require("node:events");
const {DocumentEventData} = require("./lib/eventarc-envelope");
const {createServer, notificationIdFromName, EVENT_TYPE} = require("./cloud-run-transactional-email");

function firestorePayload(notificationId = "gift_gift-123_gift_delivered") {
  return DocumentEventData.encode({
    value: {
      name: `projects/circum-2797c/databases/(default)/documents/giftEmailNotifications/${notificationId}`,
      fields: {
        notificationId: {stringValue: notificationId},
        giftId: {stringValue: "gift-123"},
        recipientEmail: {stringValue: "sender@example.com"},
        status: {stringValue: "pending"},
      },
    },
  }).finish();
}

test("extracts only gift email outbox document ids", () => {
  assert.equal(notificationIdFromName("projects/p/databases/(default)/documents/giftEmailNotifications/gift-1"), "gift-1");
  assert.equal(notificationIdFromName("projects/p/databases/(default)/documents/giftRequests/gift-1"), null);
});

test("accepts a Firestore Eventarc event and forwards the outbox record", async () => {
  let received;
  const server = createServer({
    dbFactory: () => ({unused: true}),
    processEmailOnce: async (input) => {
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
      headers: {"content-type": "application/protobuf", "ce-type": EVENT_TYPE, "ce-id": "email-event-1"},
      body: firestorePayload(),
    });
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {ok: true, status: "completed"});
    assert.equal(received.notificationId, "gift_gift-123_gift_delivered");
    assert.equal(received.after.recipientEmail, "sender@example.com");
  } finally {
    server.close();
    await once(server, "close");
  }
});

test("health is metadata-only and does not reveal secret configuration", async () => {
  const server = createServer({dbFactory: () => ({unused: true})});
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  try {
    const {port} = server.address();
    const response = await fetch(`http://127.0.0.1:${port}/health`);
    assert.equal(response.status, 200);
    const body = await response.json();
    assert.deepEqual(body.status, "ok");
    assert.equal(Object.keys(body).some((key) => /secret|key|token|from/i.test(key)), false);
  } finally {
    server.close();
    await once(server, "close");
  }
});

function claimDb(initial = {}) {
  let data = {...initial};
  let transactionQueue = Promise.resolve();
  const ref = {};
  return {
    collection: () => ({doc: () => ref}),
    runTransaction: (callback) => {
      const run = async () => callback({
        get: async () => ({exists: Object.keys(data).length > 0, data: () => data}),
        set: (_ref, value) => {
          data = {...data, ...value};
        },
        update: (_ref, value) => {
          data = {...data, ...value};
        },
      });
      const pending = transactionQueue.then(run);
      transactionQueue = pending.catch(() => {});
      return pending;
    },
    read: () => data,
  };
}

test("20 duplicate Eventarc deliveries produce one claimed email", async () => {
  const {processEmailOnce} = require("./cloud-run-transactional-email");
  const db = claimDb();
  let sends = 0;
  const results = await Promise.allSettled(Array.from({length: 20}, (_, index) => processEmailOnce({
    db,
    eventId: `event-${index}`,
    notificationId: "gift_gift-123_gift_delivered",
    after: {giftId: "gift-123"},
    deliver: async () => {
      sends += 1;
      await new Promise((resolve) => setTimeout(resolve, 5));
      return {status: "sent"};
    },
  })));
  assert.equal(sends, 1);
  assert.equal(results.filter((result) => result.status === "fulfilled" && result.value.status === "sent").length, 1);
  assert.equal(results.filter((result) => result.status === "rejected" && result.reason.statusCode === 503).length, 19);
  const duplicate = await processEmailOnce({
    db,
    eventId: "event-replay",
    notificationId: "gift_gift-123_gift_delivered",
    after: {giftId: "gift-123"},
    deliver: async () => {
      sends += 1;
      return {status: "sent"};
    },
  });
  assert.deepEqual(duplicate, {status: "duplicate"});
  assert.equal(sends, 1);
});

test("a retryable provider failure releases the claim for the next Eventarc delivery", async () => {
  const {processEmailOnce} = require("./cloud-run-transactional-email");
  const db = claimDb();
  let attempts = 0;
  await assert.rejects(processEmailOnce({
    db,
    eventId: "event-failure",
    notificationId: "gift_gift-456_gift_delivered",
    after: {giftId: "gift-456"},
    deliver: async () => {
      attempts += 1;
      throw new Error("temporary_provider_failure");
    },
  }));
  const result = await processEmailOnce({
    db,
    eventId: "event-retry",
    notificationId: "gift_gift-456_gift_delivered",
    after: {giftId: "gift-456"},
    deliver: async () => {
      attempts += 1;
      return {status: "sent"};
    },
  });
  assert.deepEqual(result, {status: "sent"});
  assert.equal(attempts, 2);
});
