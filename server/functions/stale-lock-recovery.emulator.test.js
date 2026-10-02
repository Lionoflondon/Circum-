/* eslint-disable max-len, require-jsdoc */
"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {reconcileOne} = require("./stale-lock-recovery");
async function fixture(name, run) {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST);
  const app = initializeApp({projectId: `demo-stale-lock-${name}`}, name);
  try {
await run(getFirestore(app));
} finally {
await deleteApp(app);
}
}
test("new assignment and contradictory aliases survive stale lock recovery", () => fixture("assignment", async (db) => {
  await db.doc("riderPresence/r").set({activeDeliveryId: "new", currentDeliveryId: "new", busy: true});
  assert.equal((await reconcileOne({db, riderId: "r", expectedDeliveryId: "old"})).repaired, 0);
  await db.doc("riderPresence/r").set({activeDeliveryId: "old", currentDeliveryId: "new", busy: true});
  assert.equal((await reconcileOne({db, riderId: "r", expectedDeliveryId: "old"})).conflicted, 1);
  assert.equal((await db.doc("riderPresence/r").get()).data().currentDeliveryId, "new");
}));
test("concurrent retries repair a terminal lock once and never clear collected work", () => fixture("replay", async (db) => {
  await db.doc("deliveryRequests/old").set({status: "completed"});
  await db.doc("riderPresence/r").set({activeDeliveryId: "old", busy: true, isOnline: true});
  const results = await Promise.all(Array.from({length: 4}, () => reconcileOne({db, riderId: "r", expectedDeliveryId: "old"})));
  assert.equal(results.reduce((sum, x) => sum + x.repaired, 0), 1);
  assert.equal((await db.collection("riderOperationalAudit").get()).size, 1);
  await db.doc("deliveryRequests/active").set({status: "in_transit", collectedAt: new Date()});
  await db.doc("riderPresence/r").set({activeDeliveryId: "active", busy: true});
  assert.equal((await reconcileOne({db, riderId: "r", expectedDeliveryId: "active"})).repaired, 0);
}));
