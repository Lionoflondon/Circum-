/* eslint-disable max-len */
"use strict";

const {test, before, after} = require("node:test");
const assert = require("node:assert/strict");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const ratings = require("./ratings-tipping");
const communication = require("./communication-engine");

let app;
let db;
before(() => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, "Firestore emulator required");
  app = initializeApp({projectId: "demo-tip-reconciliation"});
  db = getFirestore();
});
after(async () => {
  if (app) await deleteApp(app);
});

async function seedCardTip(id, patch = {}) {
  const tip = {
    tipId: id, deliveryId: id, senderId: `sender-${id}`, riderId: `rider-${id}`,
    amountPence: 500, amount: 5, currency: "GBP", paymentMethod: "card",
    stripePaymentIntentId: `pi_${id}`, stripeCustomerId: `cus_${id}`,
    status: "processing", credited: false, updatedAt: new Date(Date.now() - 31 * 60 * 1000),
    ...patch,
  };
  await db.doc(`deliveryRequests/${id}`).set({
    senderId: tip.senderId, riderId: tip.riderId, status: "completed", paymentStatus: "paid",
    completedAt: new Date(), currency: "GBP",
  });
  await db.doc(`deliveryTips/${id}`).set(tip);
  return tip;
}

function intentFor(tip) {
  return {
    id: tip.stripePaymentIntentId, amount: tip.amountPence, amount_received: tip.amountPence,
    livemode: true, currency: "gbp", customer: tip.stripeCustomerId, status: "succeeded",
    latest_charge: `ch_${tip.tipId}`,
    metadata: {paymentType: "delivery_tip", tipId: tip.tipId, deliveryId: tip.deliveryId,
      senderId: tip.senderId, riderId: tip.riderId},
  };
}

test("bounded dry run changes no money or cursor, then concurrent retries credit once", async (t) => {
  t.mock.method(communication, "emitNotification", async () => "fixture-notification");
  const ready = await seedCardTip("ready");
  await seedCardTip("already-credited", {status: "succeeded", credited: true});
  const stripe = {_circumStripeMode: "live",
    paymentIntents: {retrieve: async (id) => {
      assert.equal(id, ready.stripePaymentIntentId);
      return intentFor(ready);
    }},
    charges: {retrieve: async (id) => ({id, payment_intent: ready.stripePaymentIntentId,
      amount: ready.amountPence, currency: "gbp", paid: true, amount_refunded: 0})},
    refunds: {list: async () => ({data: []})},
  };
  const preview = await ratings.reconcileDeliveryTipsCore(stripe, {db, dryRun: true});
  assert.equal(preview.scanned, 2);
  assert.equal(preview.wouldRepair, 1);
  assert.equal(preview.reviewRequired, 1);
  assert.equal((await db.doc("walletTransactions/delivery_tip_ready").get()).exists, false);
  assert.equal((await db.doc("operationsState/tip_reconciliation_cursor_v2").get()).exists, false);
  assert.equal((await db.doc("tipReconciliations/tip_already-credited").get()).exists, false);

  const runs = await Promise.all([
    ratings.reconcileDeliveryTipsCore(stripe, {db}),
    ratings.reconcileDeliveryTipsCore(stripe, {db}),
  ]);
  assert.equal(runs.reduce((sum, item) => sum + item.repaired, 0), 1);
  assert.equal((await db.doc("riderEarnings/rider-ready").get()).data().availableBalance, 5);
  assert.equal((await db.doc("walletTransactions/delivery_tip_ready").get()).data().amountPence, 500);
  assert.equal((await db.doc("riderWalletTransactions/delivery_tip_ready").get()).exists, true);
  assert.equal((await db.doc("walletTransactions/delivery_tip_already-credited").get()).exists, false);
  assert.equal((await db.doc("tipReconciliations/tip_already-credited").get()).data().reason, "credited_without_ledger");
  await ratings.reconcileDeliveryTipsCore(stripe, {db});
  assert.equal((await db.doc("riderEarnings/rider-ready").get()).data().availableBalance, 5);
});

test("provider outage and malformed tip enter review without financial writes", async () => {
  await seedCardTip("provider-outage");
  await seedCardTip("malformed", {amountPence: 0});
  const stripe = {_circumStripeMode: "live", paymentIntents: {retrieve: async () => {
    throw Object.assign(new Error("provider_timeout"), {code: "ETIMEDOUT"});
  }}};
  await ratings.reconcileDeliveryTipsCore(stripe, {db});
  assert.equal((await db.doc("tipReconciliations/tip_provider-outage").get()).data().status, "review_required");
  assert.equal((await db.doc("tipReconciliations/tip_malformed").get()).data().reason, "invalid_tip_authority");
  assert.equal((await db.doc("walletTransactions/delivery_tip_provider-outage").get()).exists, false);
  assert.equal((await db.doc("walletTransactions/delivery_tip_malformed").get()).exists, false);
});

test("a captured but refunded provider charge cannot be credited by reconciliation", async () => {
  const tip = await seedCardTip("provider-refunded");
  const stripe = {_circumStripeMode: "live",
    paymentIntents: {retrieve: async () => intentFor(tip)},
    charges: {retrieve: async (id) => ({id, payment_intent: tip.stripePaymentIntentId,
      amount: tip.amountPence, currency: "gbp", paid: true, amount_refunded: 500, refunded: true})},
    refunds: {list: async () => ({data: [{id: "re_refunded"}]})},
  };
  await ratings.reconcileDeliveryTipsCore(stripe, {db});
  assert.equal((await db.doc("tipReconciliations/tip_provider-refunded").get()).data().status, "review_required");
  assert.equal((await db.doc("walletTransactions/delivery_tip_provider-refunded").get()).exists, false);
});
