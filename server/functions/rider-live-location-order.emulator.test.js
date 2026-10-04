/* eslint-disable max-len, require-jsdoc */
"use strict";
const {test, before, after} = require("node:test");
const assert = require("node:assert/strict");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
let app; let db; let endpoint;
before(() => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST);
  app = initializeApp({projectId: "demo-rider-location-order"});
  db = getFirestore(); db.settings({ignoreUndefinedProperties: true});
  endpoint = require("./delivery-tracking").updateDeliveryLiveLocation;
});
after(async () => deleteApp(app));
test("concurrent delayed locations cannot move live tracking backwards", async () => {
  const ref = db.doc("deliveryRequests/location-order");
  await ref.set({riderId: "rider", status: "in_transit"});
  const now = Date.now();
  const input = (at, latitude) => ({deliveryId: ref.id, location: {latitude, longitude: -0.1, accuracyMeters: 8, clientRecordedAt: at}});
  const context = {auth: {uid: "rider"}, app: {appId: "emulator"}};
  await Promise.all([
    endpoint.run(input(now - 2000, 51.5), context),
    endpoint.run(input(now, 51.6), context),
  ]);
  const liveRef = ref.collection("tracking").doc("liveLocation");
  const live = (await liveRef.get()).data();
  assert.equal(live.clientRecordedAt, now);
  assert.equal(live.latitude, 51.6);
  const ignored = await endpoint.run(input(now - 1000, 51.55), context);
  assert.equal(ignored.reason, "superseded");
  assert.equal((await liveRef.get()).data().latitude, 51.6);
  const stale = await endpoint.run(input(now - 180001, 51.7), context);
  assert.equal(stale.reason, "stale");
  await assert.rejects(endpoint.run(input(now + 1, 51.8), {auth: {uid: "other"}, app: {appId: "emulator"}}));
});
