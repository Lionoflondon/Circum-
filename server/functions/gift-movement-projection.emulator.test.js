/* eslint-disable max-len */
"use strict";

const {test} = require("node:test");
const assert = require("node:assert/strict");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {projectLatestGiftMovement} = require("./gift-movement-projection-core");
const {fixtureDb} = require("./gift-movement-fixture-db");

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
  assert.equal((await db.collection("giftMovementProjectionClaims").get()).size, 2);
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
  assert.equal((await db.collection("giftMovementProjectionClaims").get()).size, 2);
}));

test("deleted source cannot recreate a delivery", async () => withDb("deleted", async (db) => {
  assert.equal((await projectLatestGiftMovement(db, "missing")).status, "source_deleted");
  assert.equal((await db.doc("deliveryRequests/gift_missing").get()).exists, false);
}));

test("completed claim with missing target is surfaced for review", async () => withDb("target-missing", async (db) => {
  await db.doc("giftRequests/g3").set({status: "packed"});
  await projectLatestGiftMovement(db, "g3");
  await db.doc("deliveryRequests/gift_g3").delete();
  assert.equal((await projectLatestGiftMovement(db, "g3")).status, "projected");
  await db.doc("deliveryRequests/gift_g3").delete();
  assert.equal((await projectLatestGiftMovement(db, "g3")).status, "manual_review_claim_target_mismatch");
  assert.equal((await db.doc("deliveryRequests/gift_g3").get()).exists, false);
}));

test("fixture projection cannot write top-level customer collections", async () => withDb("fixture", async (db) => {
  const isolated = fixtureDb(db, "__codex_gift_movement_emulator");
  await isolated.collection("giftRequests").doc("__codex_gift_1").set({status: "packed"});
  assert.equal((await projectLatestGiftMovement(isolated, "__codex_gift_1")).status, "projected");
  assert.equal((await isolated.collection("deliveryRequests").doc("gift___codex_gift_1").get()).exists, true);
  assert.equal((await db.doc("deliveryRequests/gift___codex_gift_1").get()).exists, false);
  assert.equal((await db.doc("giftRequests/__codex_gift_1").get()).exists, false);
  assert.equal((await isolated.collection("giftMovementProjectionClaims").get()).size, 1);
}));
