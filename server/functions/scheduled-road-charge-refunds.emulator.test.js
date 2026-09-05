"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {initializeApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {
  settleEntitlementToRoth,
  settleEntitlementToCash,
  STATES,
  REFUND_POLICY_VERSION,
} = require("./scheduled-road-charge-refunds");

const emulator = process.env.FIRESTORE_EMULATOR_HOST;

test(
  "concurrent scheduled road-charge Roth settlement is exactly once",
  {skip: !emulator},
  async () => {
    initializeApp({projectId: "demo-retained-refunds"});
    const db = getFirestore();
    const id = `emulator-${Date.now()}`;
    await db
      .collection("roadChargeRefundEntitlements")
      .doc(id)
      .set({
        entitlementId: id,
        state: STATES.eligible,
        entitlementPence: 250,
        refundablePence: 250,
        cashRefundedPence: 0,
        rothCreditedPence: 0,
        chargeId: "blackwall_silvertown",
        policyVersion: REFUND_POLICY_VERSION,
        deliveryId: `delivery-${id}`,
        quoteId: `quote-${id}`,
        refundOwnerType: "sender",
        refundOwnerId: `owner-${id}`,
      });
    const results = await Promise.all(
      Array.from({length: 8}, () =>
        settleEntitlementToRoth({
          db,
          entitlementId: id,
          owner: {type: "sender", id: `owner-${id}`},
        }),
      ),
    );
    const transactions = await db
      .collection("walletTransactions")
      .where("entitlementId", "==", id)
      .get();
    const wallet = await db.collection("wallets").doc(`owner-${id}`).get();
    const entitlement = await db
      .collection("roadChargeRefundEntitlements")
      .doc(id)
      .get();
    assert.equal(results.filter((result) => result.settled).length, 1);
    assert.equal(transactions.size, 1);
    assert.equal(wallet.data().balance, 2.5);
    assert.equal(entitlement.data().state, STATES.rothSettled);
  },
);

async function runCashAndRothRace(db, id) {
  await db
    .collection("roadChargeRefundEntitlements")
    .doc(id)
    .set({
      entitlementId: id,
      state: STATES.eligible,
      entitlementPence: 900,
      refundablePence: 900,
      cashRefundedPence: 0,
      rothCreditedPence: 0,
      chargeId: "congestion_charge",
      policyVersion: REFUND_POLICY_VERSION,
      deliveryId: `delivery-${id}`,
      quoteId: `quote-${id}`,
      refundOwnerType: "sender",
      refundOwnerId: `owner-${id}`,
    });
  await db
    .collection("supportTickets")
    .doc(`support-case-${id}`)
    .set({
      ticketId: `support-case-${id}`,
      deliveryId: `delivery-${id}`,
      userId: `owner-${id}`,
      status: "open",
    });
  const actor = {authorized: true, uid: "support-agent-1"};
  const results = await Promise.all([
    ...Array.from({length: 4}, () =>
      settleEntitlementToCash({
        db,
        entitlementId: id,
        actor,
        customerRequestReference: `support-case-${id}`,
        cashRefundReference: `cash-ref-${id}`,
      }),
    ),
    ...Array.from({length: 4}, () =>
      settleEntitlementToRoth({
        db,
        entitlementId: id,
        owner: {type: "sender", id: `owner-${id}`},
      }),
    ),
  ]);
  const cashRefunds = await db
    .collection("roadChargeCashRefunds")
    .where("entitlementId", "==", id)
    .get();
  const transactions = await db
    .collection("walletTransactions")
    .where("entitlementId", "==", id)
    .get();
  const entitlement = await db
    .collection("roadChargeRefundEntitlements")
    .doc(id)
    .get();
  assert.equal(results.filter((result) => result.settled).length, 1);
  assert.equal(cashRefunds.size + transactions.size, 1);
  assert.ok(
    [STATES.cashSettled, STATES.rothSettled].includes(entitlement.data().state),
  );
}

test(
  "support cash exception is exactly once and cannot race Roth",
  {skip: !emulator},
  async () => {
    const db = getFirestore();
    for (let attempt = 0; attempt < 3; attempt += 1) {
      await runCashAndRothRace(db, `cash-emulator-${Date.now()}-${attempt}`);
    }
  },
);
