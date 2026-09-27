"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {queueRiderWelcomeEmail, riderWelcomeEmailId} = require("./rider-welcome-email");

function fakeDb(initial = {}, {failCreate = false} = {}) {
  const data = new Map(Object.entries(initial));
  const ref = (collection, id) => ({
    get: async () => {
      const value = data.get(`${collection}/${id}`);
      return {exists: value !== undefined, data: () => value && {...value}};
    },
    set: async (value, options = {}) => {
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

test("Rider welcome enqueue is deterministic and replay-safe", async () => {
  const db = fakeDb();
  const first = await queueRiderWelcomeEmail({
    db, uid: "rider-1", email: "rider@example.test", displayName: "Alex Example",
  });
  const second = await queueRiderWelcomeEmail({
    db, uid: "rider-1", email: "rider@example.test", displayName: "Alex Example",
  });

  assert.equal(riderWelcomeEmailId("rider-1"), "rider_welcome_rider-1");
  assert.equal(first.status, "queued");
  assert.equal(second.status, "queued");
  assert.equal(second.result, "duplicate");
  const queue = db.read("emailQueue", "rider_welcome_rider-1");
  assert.equal(queue.eventType, "rider_welcome_ready");
  assert.equal(queue.sourceRequiredStatus, "profile_started");
  assert.equal(queue.recipientRole, "rider");
  assert.equal(db.read("riderProfiles", "rider-1").welcomeEmailQueueId, "rider_welcome_rider-1");
});

test("missing Rider email is suppressed without provider work", async () => {
  const db = fakeDb();
  const result = await queueRiderWelcomeEmail({db, uid: "rider-2", email: ""});
  assert.equal(result.status, "suppressed");
  assert.equal(db.read("emailQueue", "rider_welcome_rider-2").failureReason, "invalid_recipient");
  assert.equal(db.read("riders", "rider-2").welcomeEmailStatus, "suppressed");
});

test("queue failure remains observable as pending", async () => {
  const db = fakeDb({}, {failCreate: true});
  const result = await queueRiderWelcomeEmail({db, uid: "rider-3", email: "rider3@example.test"});
  assert.equal(result.status, "pending");
  assert.equal(db.read("riderProfiles", "rider-3").welcomeEmailStatus, "pending");
});
