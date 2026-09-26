/* eslint-disable max-len */
"use strict";

const {test} = require("node:test");
const assert = require("node:assert/strict");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {projectLatestGiftMovement} = require("./gift-movement-projection-core");

async function withDb(name, run) {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, "Firestore emulator required");
  const app = initializeApp({projectId: `demo-gift-movement-${name}`}, name);
  try {
    return await run(getFirestore(app));
  } finally {
    await deleteApp(app);
  }
}

test("projects current gift once and preserves Rider voice redaction", async () => withDb("basic", async (db) => {
  await db.doc("giftRequests/g1").set({status: "packed", senderId: "sender-1", voiceNoteUrl: "private-audio"});
  const first = await projectLatestGiftMovement(db, "g1");
  assert.equal(first.status, "projected");
  const gift = (await db.doc("giftRequests/g1").get()).data();
  const delivery = (await db.doc("deliveryRequests/gift_g1").get()).data();
  assert.equal(gift.deliveryId, "gift_g1");
  assert.equal(delivery.status, "requested");
  assert.equal(delivery.matchingStatus, "available");
  assert.equal(delivery.voiceNoteUrl, undefined);
  assert.equal((await projectLatestGiftMovement(db, "g1")).status, "projected");
  assert.equal((await projectLatestGiftMovement(db, "g1")).status, "already_projected");
}));

test("delayed duplicate handlers project latest source instead of stale event status", async () => withDb("latest", async (db) => {
  await db.doc("giftRequests/g2").set({status: "packed", senderId: "sender-1"});
  await projectLatestGiftMovement(db, "g2");
  await db.doc("giftRequests/g2").update({status: "completed"});
  const results = await Promise.all([projectLatestGiftMovement(db, "g2"), projectLatestGiftMovement(db, "g2")]);
  assert.ok(results.every((result) => ["projected", "already_projected"].includes(result.status)));
  const delivery = (await db.doc("deliveryRequests/gift_g2").get()).data();
  assert.equal(delivery.status, "completed");
  assert.equal((await projectLatestGiftMovement(db, "g2")).status, "already_projected");
}));

test("deleted source cannot recreate a delivery", async () => withDb("deleted", async (db) => {
  assert.equal((await projectLatestGiftMovement(db, "missing")).status, "source_deleted");
  assert.equal((await db.doc("deliveryRequests/gift_missing").get()).exists, false);
}));
