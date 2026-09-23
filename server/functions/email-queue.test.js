"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {createEmailQueueRecord, enqueueEmail} = require("./email-queue");

function fakeDb(initial = {}) {
  const data = new Map(Object.entries(initial));
  return {
    collection: (collection) => ({doc: (id) => ({
      create: async (payload) => {
        const key = `${collection}/${id}`;
        if (data.has(key)) throw Object.assign(new Error("Already exists"), {code: 6});
        data.set(key, {...payload});
      },
    })}),
    read: (collection, id) => data.get(`${collection}/${id}`),
  };
}

test("queue publisher creates a logical item once and replay does not reset terminal state", async () => {
  const db = fakeDb({"emailQueue/logical-1": {status: "sent", providerId: "provider-1"}});
  const result = await createEmailQueueRecord(db, "logical-1", {status: "queued", to: "x@example.test"});
  assert.deepEqual(result, {status: "duplicate", notificationId: "logical-1"});
  assert.deepEqual(db.read("emailQueue", "logical-1"), {status: "sent", providerId: "provider-1"});
});

test("email queue helper returns skipped for invalid recipient without writing", async () => {
  const db = fakeDb();
  const result = await enqueueEmail(db, {id: "invalid-1", to: "invalid", subject: "Hello", textBody: "Body", eventType: "test"});
  assert.deepEqual(result, {status: "skipped", reason: "invalid_email_queue_record"});
  assert.equal(db.read("emailQueue", "invalid-1"), undefined);
});
