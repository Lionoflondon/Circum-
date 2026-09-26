/* eslint-disable max-len */
"use strict";

const {test} = require("node:test");
const assert = require("node:assert/strict");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore, Timestamp} = require("firebase-admin/firestore");
const {processNotificationRetriesCore} = require("./notification-retry-core");
const {tokenHash} = require("./device-token-authority");

async function withDb(name, run) {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, "Firestore emulator required");
  const app = initializeApp({projectId: `demo-notification-retry-${name}`}, name);
  try {
    return await run(getFirestore(app));
  } finally {
    await deleteApp(app);
  }
}

async function seed(db, id, patch = {}) {
  await db.doc(`notifications/${id}`).set({
    recipientId: "rider-1", recipientRole: "rider", type: "new_delivery",
    title: "New delivery", body: "A job is ready", data: {deliveryId: "delivery-1"},
    destination: {route: "jobs", bookingId: "delivery-1"},
    pushDeliveryStatus: "failed", retryable: true, deliveryAttempts: 1,
    createdAt: Timestamp.fromMillis(Date.now() - 30000), ...patch,
  });
}

test("concurrent worker runs send one urgent Rider push and never revive sent state", async () => withDb("concurrent", async (db) => {
  await db.doc("deliveryRequests/delivery-1").set({status: "requested"});
  await seed(db, "due");
  await seed(db, "already-sent", {pushDeliveryStatus: "sent"});
  let sends = 0;
  const options = {db, ownedToken: async () => "token-1", sendPush: async (message) => {
    sends++;
    assert.equal(message.android.priority, "high");
    assert.equal(message.apns.headers["apns-priority"], "10");
    return "fcm-1";
  }};
  const preview = await processNotificationRetriesCore({...options, dryRun: true});
  assert.equal(preview.due, 1);
  assert.equal((await db.doc("notifications/due").get()).data().pushDeliveryStatus, "failed");
  assert.equal((await db.doc("operationsState/notification_retry_cursor_v2").get()).exists, false);
  await Promise.all([processNotificationRetriesCore(options), processNotificationRetriesCore(options)]);
  assert.equal(sends, 1);
  assert.equal((await db.doc("notifications/due").get()).data().pushDeliveryStatus, "sent");
  assert.equal((await db.doc("notifications/already-sent").get()).data().pushDeliveryStatus, "sent");
  await processNotificationRetriesCore(options);
  assert.equal(sends, 1);
}));

test("permanent invalid token stops while quota rejection schedules a bounded retry", async () => withDb("failures", async (db) => {
  await seed(db, "invalid", {type: "chat_message"});
  await seed(db, "quota", {type: "chat_message"});
  await db.doc(`notificationTokens/${tokenHash("token-1")}`).set({uid: "rider-1", role: "rider", active: true});
  await processNotificationRetriesCore({db, ownedToken: async () => "token-1", sendPush: async (message) => {
    const code = message.data.notificationId === "invalid" ?
      "messaging/registration-token-not-registered" : "messaging/quota-exceeded";
    throw Object.assign(new Error("rejected"), {code});
  }});
  const invalid = (await db.doc("notifications/invalid").get()).data();
  const quota = (await db.doc("notifications/quota").get()).data();
  assert.equal(invalid.pushDeliveryStatus, "exhausted");
  assert.equal(invalid.retryable, false);
  assert.equal((await db.doc(`notificationTokens/${tokenHash("token-1")}`).get()).data().active, false);
  assert.equal(quota.pushDeliveryStatus, "failed");
  assert.equal(quota.retryable, true);
  assert.ok(quota.nextRetryAt.toMillis() > Date.now());
}));

test("expired claims recover before send and enter review after send begins", async () => withDb("lease", async (db) => {
  const expired = Timestamp.fromMillis(Date.now() - 1000);
  await seed(db, "before-send", {type: "chat_message", pushDeliveryStatus: "retrying", retryable: false,
    retryLeaseExpiresAt: expired, retrySendState: "not_started"});
  await seed(db, "after-send", {type: "chat_message", pushDeliveryStatus: "retrying", retryable: false,
    retryLeaseExpiresAt: expired, retrySendState: "started"});
  let sends = 0;
  const result = await processNotificationRetriesCore({db, ownedToken: async () => "token-1", sendPush: async () => {
    sends++;
    return "fcm-recovered";
  }});
  assert.equal(result.recovered, 1);
  assert.equal(result.uncertain, 1);
  assert.equal(sends, 1);
  assert.equal((await db.doc("notifications/before-send").get()).data().pushDeliveryStatus, "sent");
  assert.equal((await db.doc("notifications/after-send").get()).data().pushDeliveryStatus, "manual_review");
}));

test("stale offer and uncertain provider outcome never send a duplicate", async () => withDb("uncertain", async (db) => {
  await seed(db, "stale", {createdAt: Timestamp.fromMillis(Date.now() - 6 * 60000)});
  await seed(db, "timeout", {type: "chat_message"});
  let sends = 0;
  await processNotificationRetriesCore({db, ownedToken: async () => "token-1", sendPush: async () => {
    sends++;
    throw Object.assign(new Error("timeout"), {code: "ETIMEDOUT"});
  }});
  assert.equal(sends, 1);
  assert.equal((await db.doc("notifications/stale").get()).data().pushDeliveryStatus, "exhausted");
  assert.equal((await db.doc("notifications/timeout").get()).data().pushDeliveryStatus, "manual_review");
  assert.equal((await db.doc("notifications/timeout").get()).data().retryable, false);
  await processNotificationRetriesCore({db, ownedToken: async () => "token-1", sendPush: async () => {
    throw new Error("unexpected resend");
  }});
}));

test("a recently delivered job offer and an exhausted retry are skipped", async () => withDb("completed", async (db) => {
  await db.doc("deliveryRequests/delivery-1").set({status: "completed", riderId: "rider-1"});
  await seed(db, "completed-job");
  await seed(db, "max-attempts", {type: "chat_message", deliveryAttempts: 5});
  const result = await processNotificationRetriesCore({db, ownedToken: async () => "token-1", sendPush: async () => {
    throw new Error("unexpected push");
  }});
  assert.equal(result.exhausted, 2);
  assert.equal((await db.doc("notifications/completed-job").get()).data().failureReason, "stale_notification");
  assert.equal((await db.doc("notifications/max-attempts").get()).data().failureReason, "max_attempts");
}));
