/* eslint-disable max-len, require-jsdoc */
const {test, before, after} = require("node:test");
const assert = require("node:assert/strict");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {handleStripeConnectWebhook} = require("./rider-connect");
let app; let db;
before(() => {
assert.ok(process.env.FIRESTORE_EMULATOR_HOST); app = initializeApp({projectId: "demo-payout-allocation"}); db = getFirestore();
});
after(async () => {
await deleteApp(app);
});
test("bank payout events match exact earning sources and cannot recredit failed bank payouts", async (t) => {
  const oldSecret = process.env.STRIPE_WEBHOOK_SECRET;
  process.env.STRIPE_WEBHOOK_SECRET = "emulator-only";
  t.after(() => {
if (oldSecret === undefined) delete process.env.STRIPE_WEBHOOK_SECRET; else process.env.STRIPE_WEBHOOK_SECRET = oldSecret;
});
  await db.doc("riderEarnings/r1").set({availableBalance: 0, pendingWithdrawal: 5});
  await db.doc("payoutRequests/p1").set({riderId: "r1", amount: 5, status: "processing", stripeAccountId: "acct_1", destinationPaymentId: "py_1", fundsReserved: true, allocationVersion: 1});
  await db.doc("payoutRequests/unrelated").set({riderId: "r2", amount: 8, status: "processing", stripeAccountId: "acct_1", destinationPaymentId: "py_other", fundsReserved: true, allocationVersion: 1});
  await db.doc("riderPayoutAllocations/a1").set({payoutRequestId: "p1", earningId: "tip1", amountPence: 500, state: "reserved"});
  async function deliver(type, id) {
    const event = {type, id, account: "acct_1", data: {object: {id: "po_1", destination: "bank_external", automatic: true}}};
    const stripe = {webhooks: {constructEvent: () => event}, balanceTransactions: {list: () => ({autoPagingToArray: async () => [{source: "py_1"}]})}};
    const result = {code: 200, status(code) {
this.code = code; return this;
}, json(body) {
this.body = body;
}, send(body) {
this.body = body;
}};
    await handleStripeConnectWebhook(stripe)({headers: {"stripe-signature": "test"}, rawBody: Buffer.from("test")}, result);
    assert.equal(result.code, 200, JSON.stringify(result));
  }
  await deliver("payout.failed", "evt_failed");
  assert.equal((await db.doc("riderEarnings/r1").get()).data().availableBalance, 0);
  assert.equal((await db.doc("riderEarnings/r1").get()).data().pendingWithdrawal, 5);
  await deliver("payout.paid", "evt_paid");
  await deliver("payout.paid", "evt_paid");
  assert.equal((await db.doc("riderEarnings/r1").get()).data().totalWithdrawn, 5);
  assert.equal((await db.doc("riderEarnings/r1").get()).data().pendingWithdrawal, 0);
  assert.equal((await db.doc("riderPayoutAllocations/a1").get()).data().state, "paid");
  assert.equal((await db.doc("payoutRequests/unrelated").get()).data().status, "processing");
});
test("actual payout callable reserves FIFO identities once and protects the whole tip", async () => {
  const riderId = "fifo-rider";
  await db.doc("adminUsers/emulator-admin").set({active: true});
  await db.doc(`riderProfiles/${riderId}`).set({approvalStatus: "approved", internalOnboardingComplete: true,
    vehicleType: "car", identityApproved: true, stripeConnectAccountId: "acct_fifo", stripeDetailsSubmitted: true,
    stripeChargesEnabled: true, stripePayoutsEnabled: true});
  for (const documentType of ["driving_licence", "insurance", "registration_v5c", "mot", "right_to_work", "identity"]) {
    await db.doc(`riderDocuments/fifo-${documentType}`).set({riderId, documentType, status: "approved"});
  }
  await db.doc(`riderEarnings/${riderId}`).set({availableBalance: 10, pendingWithdrawal: 0});
  await db.doc("riderEarningTransactions/base-fifo").set({riderId, type: "delivery_earning", amount: 5, transactionId: "base-fifo", deliveryId: "base-delivery", createdAt: new Date(1000)});
  await db.doc("riderWalletTransactions/tip-fifo").set({riderId, type: "tip", amount: 5, amountPence: 500, transactionId: "tip-fifo", deliveryId: "tip-fifo", tipId: "tip-fifo", createdAt: new Date(2000)});
  await db.doc("deliveryTips/tip-fifo").set({riderId, status: "succeeded", amountPence: 500});
  const calls = [];
  const stripe = {transfers: {create: async (data, options) => {
    calls.push({data, options}); return {id: "tr_fifo", destination_payment: "py_fifo"};
  }}};
  const callable = require("./rider-connect").createRiderTransferOrPayout(stripe);
  const input = {riderId, requestId: "fifo-request", amount: 10, estimatedStripeFees: 1};
  const context = {auth: {uid: "emulator-admin", token: {}}, app: {appId: "emulator"}};
  await callable.run(input, context);
  await callable.run(input, context);
  assert.equal(calls.length, 1);
  const request = (await db.doc("payoutRequests/fifo-request").get()).data();
  assert.deepEqual(request.earningAllocations.map((a) => a.earningId), ["base-fifo", "tip-fifo"]);
  assert.equal(request.earningAllocations[1].amountPence, 500);
  assert.equal(request.earningAllocations[1].processorFeePence, 0);
  assert.equal(request.earningAllocations[1].netAmountPence, 500);
  assert.equal((await db.doc(`riderEarnings/${riderId}`).get()).data().availableBalance, 0);
  assert.equal((await db.doc(`riderEarnings/${riderId}`).get()).data().pendingWithdrawal, 10);
  assert.equal((await db.collection("riderPayoutAllocations").where("payoutRequestId", "==", "fifo-request").get()).size, 2);
});
test("unlinked historical payout debits cannot be silently allocated a second time", async () => {
  const riderId = "orphan-history";
  await db.doc("riderEarningTransactions/orphan-base").set({riderId, type: "delivery_earning", amount: 10, transactionId: "orphan-base", createdAt: new Date(1000)});
  await db.doc("riderWalletTransactions/orphan-withdrawal").set({riderId, type: "withdrawal", amount: -5, createdAt: new Date(2000)});
  await assert.rejects(db.runTransaction((tx) => require("./rider-payout-allocation").readAllocationPlan(tx, db, riderId, "new-request", 500)), /Historical payout ledger requires reconciliation/);
  assert.equal((await db.doc("payoutRequests/new-request").get()).exists, false);
});
