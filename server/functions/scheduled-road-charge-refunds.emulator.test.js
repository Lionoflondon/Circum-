"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {initializeApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {settleEntitlementToRoth, STATES} = require("./scheduled-road-charge-refunds");

const emulator = process.env.FIRESTORE_EMULATOR_HOST;

test("concurrent scheduled road-charge Roth settlement is exactly once", {skip: !emulator}, async () => {
  initializeApp({projectId: "circum-2797c"});
  const db = getFirestore();
  const id = `emulator-${Date.now()}`;
  await db.collection("roadChargeRefundEntitlements").doc(id).set({
    entitlementId: id,
    state: STATES.eligible,
    entitlementPence: 250,
    refundablePence: 250,
    cashRefundedPence: 0,
    rothCreditedPence: 0,
    deliveryId: `delivery-${id}`,
    quoteId: `quote-${id}`,
    chargeId: "blackwall_silvertown",
    refundOwnerType: "sender",
    refundOwnerId: `owner-${id}`,
  });
  const results = await Promise.all(Array.from({length: 8}, () =>
    settleEntitlementToRoth({db, entitlementId: id, owner: {type: "sender", id: `owner-${id}`}})));
  const transactions = await db.collection("walletTransactions").where("entitlementId", "==", id).get();
  const wallet = await db.collection("wallets").doc(`owner-${id}`).get();
  const entitlement = await db.collection("roadChargeRefundEntitlements").doc(id).get();
  assert.equal(results.filter((result) => result.settled).length, 1);
  assert.equal(transactions.size, 1);
  assert.equal(wallet.data().balance, 2.5);
  assert.equal(entitlement.data().state, STATES.rothSettled);
});
