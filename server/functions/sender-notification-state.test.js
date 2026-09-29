"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {updateSenderNotificationState} = require("./sender-notification-state");

function fakeDb(initial = {}) {
  const records = new Map(Object.entries(initial).map(([id, data]) => [id, {...data}]));
  const events = [];
  const db = {
    collection(name) {
      return {
        doc(id) {
          const key = id || `${name}-${events.length}`;
          return {path: `${name}/${key}`, id: key, collection: name};
        },
      };
    },
    async runTransaction(work) {
      const transaction = {
        get: async (ref) => {
          const data = records.get(ref.id);
          return {exists: data != null, data: () => data && {...data}};
        },
        set: (ref, patch) => {
          if (ref.collection === "senderNotificationEvents") events.push(patch);
          else records.set(ref.id, {...(records.get(ref.id) || {}), ...patch});
        },
      };
      await work(transaction);
    },
    record(id) {
      return records.get(id);
    },
    events,
  };
  return db;
}

const ctx = (uid) => ({auth: {uid}});
const stamp = {seconds: 123};

test("mark_read and archive are owner-bound, idempotent, and preserve content", async () => {
  const db = fakeDb({
    n1: {recipientId: "sender-1", recipientRole: "shipper", title: "Delivery", type: "delivery_created", data: {deliveryId: "d1"}},
  });

  const firstRead = await updateSenderNotificationState({notificationId: "n1", action: "mark_read"}, ctx("sender-1"), {db, serverTimestamp: () => stamp});
  const duplicateRead = await updateSenderNotificationState({notificationId: "n1", action: "mark_read"}, ctx("sender-1"), {db, serverTimestamp: () => stamp});
  const firstArchive = await updateSenderNotificationState({notificationId: "n1", action: "archive"}, ctx("sender-1"), {db, serverTimestamp: () => stamp});
  const duplicateArchive = await updateSenderNotificationState({notificationId: "n1", action: "archive"}, ctx("sender-1"), {db, serverTimestamp: () => stamp});

  assert.equal(firstRead.changed, true);
  assert.equal(duplicateRead.changed, false);
  assert.equal(firstArchive.changed, true);
  assert.equal(duplicateArchive.changed, false);
  assert.deepEqual(db.record("n1"), {
    recipientId: "sender-1", recipientRole: "shipper", title: "Delivery", type: "delivery_created", data: {deliveryId: "d1"},
    read: true, readAt: stamp, archived: true, archivedAt: stamp,
  });
  assert.equal(db.events.length, 2);
});

test("wrong owner, missing notification, malformed action, and protected fields fail closed", async () => {
  const db = fakeDb({n1: {recipientId: "sender-1", recipientRole: "sender", title: "Original"}});
  await assert.rejects(updateSenderNotificationState({notificationId: "n1", action: "mark_read"}, ctx("sender-2"), {db}), {code: "permission-denied"});
  await assert.rejects(updateSenderNotificationState({notificationId: "missing", action: "mark_read"}, ctx("sender-1"), {db}), {code: "not-found"});
  await assert.rejects(updateSenderNotificationState({notificationId: "n1", action: "dismiss"}, ctx("sender-1"), {db}), {code: "invalid-argument"});
  await assert.rejects(updateSenderNotificationState({notificationId: "n1", action: "mark_read", recipientId: "attacker"}, ctx("sender-1"), {db}), {code: "invalid-argument"});
});

test("missing Auth is rejected before any Firestore access", async () => {
  let accessed = false;
  const db = fakeDb({n1: {recipientId: "sender-1"}});
  db.runTransaction = async () => {
    accessed = true;
  };
  await assert.rejects(updateSenderNotificationState({notificationId: "n1", action: "mark_read"}, {}, {db}), {code: "unauthenticated"});
  assert.equal(accessed, false);
});
