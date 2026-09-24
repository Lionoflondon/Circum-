"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {queueSenderWelcomeEmail, welcomeEmailId} = require("./sender-welcome-email");

function fakeDb(initial = {}, {failCreate = false} = {}) {
  const data = new Map(Object.entries(initial));
  const ref = (collection, id) => ({
    get: async () => {
      const value = data.get(`${collection}/${id}`);
      return {exists: value !== undefined, data: () => value && {...value}};
    },
    set: async (value, options = {}) => {
      if (failCreate && collection === "emailQueue") throw new Error("queue unavailable");
      const key = `${collection}/${id}`;
      data.set(key, options.merge ? {...(data.get(key) || {}), ...value} : {...value});
    },
    create: async (value) => {
      if (failCreate) throw new Error("queue unavailable");
      const key = `${collection}/${id}`;
      if (data.has(key)) throw Object.assign(new Error("Already exists"), {code: 6});
      data.set(key, {...value});
    },
  });
  return {
    collection: (collection) => ({doc: (id) => ref(collection, id)}),
    read: (collection, id) => data.get(`${collection}/${id}`),
  };
}

test("welcome enqueue is deterministic and replay-safe", async () => {
  const db = fakeDb();
  const first = await queueSenderWelcomeEmail({
    db, uid: "sender-1", email: "sender@example.test", displayName: "Alex Example",
    starterRothTransactionId: "sender_welcome_roth_sender-1",
  });
  const second = await queueSenderWelcomeEmail({
    db, uid: "sender-1", email: "sender@example.test", displayName: "Alex Example",
    starterRothTransactionId: "sender_welcome_roth_sender-1",
  });
  assert.equal(welcomeEmailId("sender-1"), "sender_welcome_sender-1");
  assert.equal(first.status, "queued");
  assert.equal(second.status, "queued");
  assert.equal(second.result, "duplicate");
  const queue = db.read("emailQueue", "sender_welcome_sender-1");
  assert.equal(queue.status, "queued");
  assert.equal(queue.eventType, "sender_welcome_ready");
  assert.equal(queue.sourceRequiredFields.starterRothGrantStatus, "granted");
  assert.equal(db.read("users", "sender-1").welcomeEmailQueueId, "sender_welcome_sender-1");
});

test("missing or suppressed recipients are terminally persisted without provider work", async () => {
  const missingDb = fakeDb();
  const missing = await queueSenderWelcomeEmail({
    db: missingDb, uid: "sender-2", email: "", starterRothTransactionId: "grant-2",
  });
  assert.equal(missing.status, "suppressed");
  assert.equal(missingDb.read("emailQueue", "sender_welcome_sender-2").failureReason, "invalid_recipient");
  assert.equal(missingDb.read("users", "sender-2").welcomeEmailStatus, "suppressed");

  const suppressedDb = fakeDb();
  const suppressed = await queueSenderWelcomeEmail({
    db: suppressedDb, uid: "sender-3", email: "sender3@example.test", recipientSuppressed: true,
    suppressionReason: "account_suppressed", starterRothTransactionId: "grant-3",
  });
  assert.equal(suppressed.status, "suppressed");
  assert.equal(suppressedDb.read("emailQueue", "sender_welcome_sender-3").failureReason, "account_suppressed");
});

test("queue failure leaves account welcome pending for a later bootstrap repair", async () => {
  const db = fakeDb({}, {failCreate: true});
  const result = await queueSenderWelcomeEmail({
    db, uid: "sender-4", email: "sender4@example.test", starterRothTransactionId: "grant-4",
  });
  assert.equal(result.status, "pending");
  assert.equal(db.read("users", "sender-4").welcomeEmailStatus, "pending");
});

test("no welcome queue is created before the authoritative Starter Roth grant exists", async () => {
  const db = fakeDb();
  const result = await queueSenderWelcomeEmail({db, uid: "sender-5", email: "sender5@example.test"});
  assert.deepEqual(result, {status: "blocked", reason: "starter_roth_not_final", notificationId: "sender_welcome_sender-5"});
  assert.equal(db.read("emailQueue", "sender_welcome_sender-5"), undefined);
});
