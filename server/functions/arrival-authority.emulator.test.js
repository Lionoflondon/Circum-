/* eslint-disable max-len, require-jsdoc */
"use strict";
const {test, before, after} = require("node:test");
const assert = require("node:assert/strict");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const policy = require("./delivery-policy");
const notifications = require("./platform-notifications");
let app; let db;
before(() => {
 assert.ok(process.env.FIRESTORE_EMULATOR_HOST); app = initializeApp({projectId: "demo-arrival-authority"}); db = getFirestore(); db.settings({ignoreUndefinedProperties: true});
});
after(async () => {
 await deleteApp(app);
});
test("arrival clock is persisted once and shared by waiting and Sender notification", async () => {
  const ref = db.doc("deliveryRequests/arrival");
  await ref.set({senderId: "sender", riderId: "rider", status: "navigating_to_pickup", pickupLocation: {lat: 51.5, lng: -0.1}});
  await db.doc("chats/arrival").set({participants: ["sender", "rider"]});
  const before = await ref.get();
  const input = {deliveryId: ref.id, phase: "pickup", location: {lat: 51.5, lng: -0.1, clientRecordedAt: Date.now()}, gpsAccuracyMeters: 5};
  await assert.rejects(policy.recordRiderArrival.run(input, {auth: {uid: "wrong"}, app: {appId: "emulator"}}));
  const ctx = {auth: {uid: "rider"}, app: {appId: "emulator"}};
  const results = await Promise.all([policy.recordRiderArrival.run(input, ctx), policy.recordRiderArrival.run(input, ctx)]);
  assert.ok(results.every((r) => r.success));
  const after = await ref.get(); const row = after.data();
  assert.equal(row.arrivedAt.toMillis(), row.waiting.startedAt);
  assert.equal(row.pickupArrivedAt.toMillis(), row.waiting.startedAt);
  await notifications.onDeliveryUpdated.run({before, after});
  await notifications.onDeliveryUpdated.run({before, after});
  const alias = {id: after.id, data: () => ({...row, status: "rider_arrived_pickup"})};
  await notifications.onDeliveryUpdated.run({before: after, after: alias});
  const records = await db.collection("notifications").where("recipientId", "==", "sender").get();
  assert.equal(records.size, 1, JSON.stringify(records.docs.map((doc) => ({id: doc.id, type: doc.data().type, key: doc.data().dedupeKey}))));
  assert.equal((await db.collection("chats/arrival/messages").get()).size, 1);
  assert.equal(Number(records.docs[0].data().data.arrivedAt), row.waiting.startedAt);
  const charged = {id: after.id, data: () => ({...row, noShowFinancial: {amount: 7, currency: "GBP"}})};
  await notifications.onDeliveryUpdated.run({before: after, after: charged});
  await notifications.onDeliveryUpdated.run({before: after, after: charged});
  assert.equal((await db.collection("notifications").where("type", "==", "waiting_charge_updated").get()).size, 1);
  await policy.recordRiderArrival.run(input, ctx);
  assert.equal((await ref.get()).data().arrivedAt.toMillis(), row.waiting.startedAt);
});
