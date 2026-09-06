/* eslint-disable max-len, require-jsdoc */
const {test, before, after} = require("node:test");
const assert = require("node:assert/strict");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const ratings = require("./ratings-tipping");
const refunds = require("./tip-refunds");
const communication = require("./communication-engine");
let app; let db;
before(() => {
assert.ok(process.env.FIRESTORE_EMULATOR_HOST, "Emulator required"); app = initializeApp({projectId: "demo-tip-authority"}); db = getFirestore();
});
after(async () => {
if (app) await deleteApp(app);
});
async function seedTip(id, amountPence = 500) {
  const tip = {tipId: id, deliveryId: id, senderId: `s-${id}`, riderId: `r-${id}`, amountPence, amount: amountPence / 100,
    currency: "GBP", paymentMethod: "card", stripePaymentIntentId: `pi_${id}`, stripeCustomerId: `cus_${id}`, status: "processing"};
  await db.doc(`deliveryRequests/${id}`).set({senderId: tip.senderId, riderId: tip.riderId, status: "completed", paymentStatus: "paid", completedAt: new Date()});
  await db.doc(`deliveryTips/${id}`).set(tip);
  return {tip, intent: {id: tip.stripePaymentIntentId, amount: amountPence, amount_received: amountPence, livemode: true, currency: "gbp", customer: tip.stripeCustomerId, status: "succeeded",
    metadata: {paymentType: "delivery_tip", tipId: id, deliveryId: id, senderId: tip.senderId, riderId: tip.riderId}}};
}
test("50 seeded concurrent tip confirmations credit one earning per payment", async (t) => {
  t.mock.method(communication, "emitNotification", async () => "test-notification");
  const run = db.runTransaction.bind(db);
  let retries = 0;
  t.mock.method(db, "runTransaction", async (callback, options) => {
    let attempts = 0;
    try {
return await run((tx) => {
attempts++; return callback(tx);
}, options);
} finally {
retries += Math.max(0, attempts - 1);
}
  });
  for (let seed = 1; seed <= 50; seed++) {
    const {tip, intent} = await seedTip(`seed-${seed}`, 100 + seed * 17);
    const results = await Promise.allSettled(Array.from({length: 8}, () => ratings.processStripeTipIntent({}, intent)));
    assert.equal(results.filter((r) => r.status === "rejected").length, 0, `seed ${seed}: ${JSON.stringify(results)}`);
    const earnings = (await db.doc(`riderEarnings/${tip.riderId}`).get()).data();
    assert.equal(earnings.availableBalance, tip.amountPence / 100);
    assert.equal(earnings.tipCount, 1);
    assert.equal((await db.collection("riderWalletTransactions").where("riderId", "==", tip.riderId).get()).size, 1);
  }
  t.diagnostic(`Terminal passes: 50/50; successful SDK transaction retries: ${retries}`);
});
test("refund reversal is idempotent and records recovery after payout", async (t) => {
  t.mock.method(communication, "emitNotification", async () => "test-notification");
  const {tip, intent} = await seedTip("refund");
  await ratings.processStripeTipIntent({}, intent);
  await db.doc(`riderEarnings/${tip.riderId}`).update({availableBalance: 0, availableEarnings: 0});
  await db.doc("riderPayoutAllocations/paid-refund").set({earningId: `delivery_tip_${tip.deliveryId}`, riderId: tip.riderId, payoutRequestId: "paid-refund", amountPence: 500, state: "paid", kind: "payout"});
  const results = await Promise.allSettled(Array.from({length: 8}, () => refunds.reverseTipEarning({db, tipId: tip.tipId, amountPence: 500, providerReference: "re_1", reason: "duplicate_charge"})));
  assert.equal(results.filter((r) => r.status === "rejected").length, 0);
  const wallet = (await db.doc(`riderEarnings/${tip.riderId}`).get()).data();
  assert.equal(wallet.availableBalance, -5);
  assert.equal(wallet.tipRecoveryPence, 500);
  await ratings.processStripeTipIntent({}, intent);
  assert.equal((await db.doc(`riderEarnings/${tip.riderId}`).get()).data().availableBalance, -5);
});
test("capture after cancellation refunds fully without creating rider earnings", async () => {
  const {tip, intent} = await seedTip("cancelled-capture");
  await db.doc(`deliveryRequests/${tip.deliveryId}`).set({senderId: tip.senderId, riderId: tip.riderId, status: "cancelled", paymentStatus: "refunded"});
  const calls = [];
  const stripe = {refunds: {create: async (data, options) => {
calls.push({data, options}); return {id: "re_cancel", status: "succeeded"};
}}};
  const result = await ratings.processStripeTipIntent(stripe, intent);
  assert.equal(result.status, "refunded");
  assert.equal(calls[0].data.amount, tip.amountPence);
  assert.equal((await db.doc(`riderEarnings/${tip.riderId}`).get()).exists, false);
  assert.equal((await db.doc(`walletTransactions/delivery_tip_${tip.deliveryId}`).get()).exists, false);
  assert.equal((await db.doc(`walletTransactions/tip_reversal_${tip.tipId}_${tip.amountPence}`).get()).exists, true);
});
test("mixed-funded delivery does not reduce the separately captured tip", async (t) => {
  t.mock.method(communication, "emitNotification", async () => "test-notification");
  const {tip, intent} = await seedTip("mixed-delivery");
  await db.doc(`deliveryRequests/${tip.deliveryId}`).update({rothContribution: 7, stripeContribution: 13});
  await ratings.processStripeTipIntent({}, intent);
  assert.equal((await db.doc(`riderEarnings/${tip.riderId}`).get()).data().availableBalance, 5);
  const delivery = (await db.doc(`deliveryRequests/${tip.deliveryId}`).get()).data();
  assert.equal(delivery.rothContribution, 7);
  assert.equal(delivery.stripeContribution, 13);
});
test("partially paid tip reverses unpaid funds and records only paid recovery", async (t) => {
  t.mock.method(communication, "emitNotification", async () => "test-notification");
  const {tip, intent} = await seedTip("partial-paid");
  await ratings.processStripeTipIntent({}, intent);
  await db.doc(`riderEarnings/${tip.riderId}`).update({availableBalance: 3, availableEarnings: 3});
  await db.doc("riderPayoutAllocations/partial-paid").set({earningId: `delivery_tip_${tip.deliveryId}`, riderId: tip.riderId, payoutRequestId: "partial-paid", amountPence: 200, state: "paid", kind: "payout"});
  await refunds.reverseTipEarning({db, tipId: tip.tipId, amountPence: 500, providerReference: "re_partial_paid", reason: "fraud"});
  const saved = (await db.doc(`deliveryTips/${tip.tipId}`).get()).data();
  assert.equal(saved.unpaidReversedPence, 300);
  assert.equal(saved.paidReversedPence, 200);
  assert.equal((await db.doc(`riderEarnings/${tip.riderId}`).get()).data().availableBalance, -2);
  assert.equal((await db.doc(`tipRecoveries/tip_reversal_${tip.tipId}_500`).get()).data().amountPence, 200);
});
test("provider return racing a paid webhook restores the returned cash once", async (t) => {
  t.mock.method(communication, "emitNotification", async () => "test-notification");
  const {tip, intent} = await seedTip("paid-return-race");
  await ratings.processStripeTipIntent({}, intent);
  await db.doc(`riderEarnings/${tip.riderId}`).update({availableBalance: 0, availableEarnings: 0, totalWithdrawn: 5, pendingWithdrawal: 0});
  await db.doc("payoutRequests/paid-return-race").set({riderId: tip.riderId, amount: 5, riderNetPayout: 5, status: "paid", stripeTransferId: "tr_race"});
  await db.doc("riderPayoutAllocations/paid-return-race").set({earningId: `delivery_tip_${tip.deliveryId}`, riderId: tip.riderId,
    payoutRequestId: "paid-return-race", amountPence: 500, state: "paid", kind: "payout", providerReturnedPence: 500, providerReturnId: "trr_race"});
  for (let i = 0; i < 2; i++) await refunds.reverseTipEarning({db, tipId: tip.tipId, amountPence: 500, providerReference: "re_race", reason: "fraud"});
  const balance = (await db.doc(`riderEarnings/${tip.riderId}`).get()).data();
  assert.equal(balance.availableBalance, 0);
  assert.equal(balance.pendingWithdrawal, 0);
  assert.equal(balance.totalWithdrawn, 0);
  assert.equal(balance.tipRecoveryPence, 0);
  assert.equal((await db.doc("walletTransactions/tip_provider_return_paid-return-race_500").get()).data().amountPence, 500);
});
test("refunding an earning used for earlier tip recovery restores that exact debt once", async (t) => {
  t.mock.method(communication, "emitNotification", async () => "test-notification");
  const {tip, intent} = await seedTip("recovery-chain");
  await ratings.processStripeTipIntent({}, intent);
  await db.doc(`riderEarnings/${tip.riderId}`).update({availableBalance: 3, availableEarnings: 3});
  await db.doc("tipRecoveries/original-debt").set({riderId: tip.riderId, amountPence: 200, unallocatedPence: 0});
  await db.doc("riderPayoutAllocations/recovery-chain").set({earningId: `delivery_tip_${tip.deliveryId}`, riderId: tip.riderId,
    payoutRequestId: "recovery_original-debt", amountPence: 200, state: "paid", kind: "tip_recovery"});
  for (let i = 0; i < 2; i++) await refunds.reverseTipEarning({db, tipId: tip.tipId, amountPence: 500, providerReference: "re_chain", reason: "fraud"});
  assert.equal((await db.doc("tipRecoveries/original-debt").get()).data().unallocatedPence, 200);
  assert.equal((await db.doc("riderPayoutAllocations/recovery-chain").get()).data().refundedPence, 200);
  assert.equal((await db.doc(`riderEarnings/${tip.riderId}`).get()).data().availableBalance, -2);
  assert.equal((await db.doc(`deliveryTips/${tip.tipId}`).get()).data().paidReversedPence, 0);
});
test("a support refund after a partial refund requests only the remainder", async (t) => {
  t.mock.method(communication, "emitNotification", async () => "test-notification");
  const {tip, intent} = await seedTip("remaining-refund");
  await ratings.processStripeTipIntent({}, intent);
  await refunds.reverseTipEarning({db, tipId: tip.tipId, amountPence: 200, providerReference: "re_partial", reason: "fraud"});
  const amounts = [];
  const stripe = {refunds: {create: async (data) => {
 amounts.push(data.amount); return {id: "re_remainder", status: "succeeded"};
}}};
  await refunds.refundCapturedTip({db, stripe, tipId: tip.tipId, reason: "fraud", actorId: "support"});
  await refunds.refundCapturedTip({db, stripe, tipId: tip.tipId, reason: "fraud", actorId: "support"});
  assert.deepEqual(amounts, [300]);
  assert.equal((await db.doc(`riderEarnings/${tip.riderId}`).get()).data().availableBalance, 0);
});
test("lost processor dispute reverses a tip once while a won dispute preserves earnings", async (t) => {
  t.mock.method(communication, "emitNotification", async () => "test-notification");
  for (const status of ["lost", "won"]) {
    const {tip, intent} = await seedTip(`dispute-${status}`);
    await ratings.processStripeTipIntent({}, intent);
    const stripe = {disputes: {retrieve: async () => ({id: `du_${status}`, charge: `ch_${status}`, amount: 500, currency: "gbp", status})},
      charges: {retrieve: async () => ({id: `ch_${status}`, payment_intent: intent.id, amount: 500, amount_refunded: 0})},
      paymentIntents: {retrieve: async () => intent}};
    const event = {id: `evt_${status}`, type: "charge.dispute.closed", data: {object: {id: `du_${status}`}}};
    await ratings.processStripeTipDispute(stripe, event);
    await ratings.processStripeTipDispute(stripe, event);
    assert.equal((await db.doc(`riderEarnings/${tip.riderId}`).get()).data().availableBalance, status === "lost" ? 0 : 5);
    assert.equal((await db.doc(`tipDisputes/du_${status}`).get()).data().status, status);
  }
});
test("concurrent partial and full transfer returns keep stable provider request amounts", async (t) => {
  t.mock.method(communication, "emitNotification", async () => "test-notification");
  const {tip, intent} = await seedTip("concurrent-returns");
  await ratings.processStripeTipIntent({}, intent);
  await db.doc(`riderEarnings/${tip.riderId}`).update({availableBalance: 0, availableEarnings: 0, pendingWithdrawal: 5});
  await db.doc("payoutRequests/concurrent-returns").set({riderId: tip.riderId, amount: 5, riderNetPayout: 5,
    status: "processing", stripeTransferId: "tr_concurrent", fundsReserved: true});
  await db.doc("riderPayoutAllocations/concurrent-returns").set({earningId: `delivery_tip_${tip.deliveryId}`, riderId: tip.riderId,
    payoutRequestId: "concurrent-returns", amountPence: 500, state: "reserved", kind: "payout"});
  let returned = 0;
  const requests = new Map();
  const stripe = {transfers: {createReversal: async (_id, data, options) => {
    const previous = requests.get(options.idempotencyKey);
    if (previous) {
 assert.equal(previous.amount, data.amount); return {id: previous.id};
}
    returned += data.amount;
    assert.ok(returned <= 500);
    const id = `trr_${requests.size}`;
    requests.set(options.idempotencyKey, {id, amount: data.amount});
    return {id};
  }}};
  await Promise.all([200, 500, 200, 500].map((amountPence) => refunds.returnUnpaidTipAllocations({db, stripe, tipId: tip.tipId, amountPence})));
  await refunds.reverseTipEarning({db, tipId: tip.tipId, amountPence: 500, providerReference: "re_concurrent", reason: "fraud"});
  assert.equal(returned, 500);
  const wallet = (await db.doc(`riderEarnings/${tip.riderId}`).get()).data();
  assert.equal(wallet.availableBalance, 0);
  assert.equal(wallet.pendingWithdrawal, 0);
  const audit = await db.collection("tipTransferReturns").where("tipId", "==", tip.tipId).get();
  assert.equal(audit.docs.reduce((total, doc) => total + doc.data().amountPence, 0), 500);
});
test("partial chargeback followed by refund reverses the combined amount without double recovery", async (t) => {
  t.mock.method(communication, "emitNotification", async () => "test-notification");
  const {tip, intent} = await seedTip("dispute-and-refund");
  await ratings.processStripeTipIntent({}, intent);
  const charge = {id: "ch_combined", payment_intent: intent.id, currency: "gbp", amount: 500, amount_refunded: 0};
  const stripe = {disputes: {retrieve: async () => ({id: "du_combined", charge: charge.id, amount: 200, currency: "gbp", status: "lost"})},
    charges: {retrieve: async () => charge}, paymentIntents: {retrieve: async () => intent}};
  await ratings.processStripeTipDispute(stripe, {id: "evt_combined", data: {object: {id: "du_combined"}}});
  assert.equal((await db.doc(`riderEarnings/${tip.riderId}`).get()).data().availableBalance, 3);
  charge.amount_refunded = 300;
  const event = {data: {object: charge}};
  await ratings.processStripeTipRefund(stripe, event);
  await ratings.processStripeTipRefund(stripe, event);
  assert.equal((await db.doc(`riderEarnings/${tip.riderId}`).get()).data().availableBalance, 0);
  assert.equal((await db.doc(`deliveryTips/${tip.tipId}`).get()).data().reversedPence, 500);
});
for (let rothSeed = 0; rothSeed < 50; rothSeed++) {
test(`Roth tip debit and restoration use the real ledger exactly once ${rothSeed}`, async (t) => {
  const runTransaction = db.runTransaction.bind(db);
  let successfulRetries = 0;
  t.mock.method(db, "runTransaction", async (callback, options) => {
    let attempts = 0;
    try {
      const value = await runTransaction((tx) => {
 attempts++; return callback(tx);
}, options);
      successfulRetries += Math.max(0, attempts - 1);
      return value;
    } catch (error) {
      t.diagnostic(`Roth tip transaction failure: ${error.code}: ${error.message}`);
      throw error;
    }
  });
  t.mock.method(communication, "emitNotification", async () => "test-notification");
  t.mock.method(require("firebase-admin/auth").getAuth(), "getUser", async (uid) => ({uid}));
  const tipId = `roth-tip-${rothSeed}`;
  const senderId = `${tipId}-sender`; const riderId = `${tipId}-rider`;
  await db.doc(`deliveryRequests/${tipId}`).set({senderId, riderId, status: "completed", paymentStatus: "paid", currency: "GBP", completedAt: new Date(), rothAppliedAmount: 7, remainingAmount: 13});
  await db.doc(`wallets/${senderId}`).set({uid: senderId, balance: 10, rothCredit: 10});
  const callable = ratings.submitDeliveryTip({});
  const context = {auth: {uid: senderId, token: {}}, app: {appId: "emulator"}};
  const input = {deliveryId: tipId, amountPence: 500, paymentMethod: "roth"};
  const results = await Promise.allSettled(Array.from({length: 8}, () => callable.run(input, context)));
  assert.equal(results.filter((result) => result.status === "rejected").length, 0, JSON.stringify(results));
  assert.equal((await db.doc(`wallets/${senderId}`).get()).data().balance, 5);
  assert.equal((await db.doc(`riderEarnings/${riderId}`).get()).data().availableBalance, 5);
  for (let i = 0; i < 2; i++) await refunds.refundCapturedTip({db, stripe: {}, tipId, reason: "fraud", actorId: "support"});
  assert.equal((await db.doc(`wallets/${senderId}`).get()).data().balance, 10);
  assert.equal((await db.doc(`riderEarnings/${riderId}`).get()).data().availableBalance, 0);
  assert.equal((await db.doc(`walletTransactions/tip_refund_${tipId}`).get()).exists, true);
  assert.equal((await db.doc(`deliveryRequests/${tipId}`).get()).data().rothAppliedAmount, 7);
  assert.equal((await db.doc(`deliveryRequests/${tipId}`).get()).data().remainingAmount, 13);
  t.diagnostic(`Roth seed ${rothSeed}: terminal pass; successful SDK transaction retries: ${successfulRetries}`);
});
}
test("tip callable rejects invalid money, participants and delivery contexts before reservation", async () => {
  const variants = [
    {auth: false}, {uid: "wrong-sender"}, {input: {riderId: "wrong-rider"}}, {input: {senderId: "wrong-sender"}},
    {input: {amountPence: -1}}, {input: {amountPence: 10001}}, {input: {amountPence: 100.5}}, {input: {amountPence: NaN}},
    {input: {currency: "USD"}}, {delivery: {currency: "USD"}}, {delivery: {paymentStatus: "unpaid"}},
    {delivery: {status: "cancelled", deliveryState: "completed"}}, {delivery: {status: "failed"}},
    {delivery: {riderId: ""}}, {delivery: {assignedRiderId: "other"}}, {delivery: {isTest: true}}, {delivery: {refundStatus: "refunded"}},
  ];
  for (let i = 0; i < variants.length; i++) {
    const variant = variants[i]; const id = `denied-tip-${i}`;
    await db.doc(`deliveryRequests/${id}`).set({senderId: "owner", riderId: "assigned", status: "completed", paymentStatus: "paid", completedAt: new Date(), ...variant.delivery});
    const context = variant.auth === false ? {} : {auth: {uid: variant.uid || "owner", token: {}}, app: {appId: "emulator"}};
    await assert.rejects(ratings.submitDeliveryTip({}).run({deliveryId: id, amountPence: 500, paymentMethod: "card", ...variant.input}, context));
    assert.equal((await db.doc(`deliveryTips/${id}`).get()).exists, false, `invalid case ${i} created a tip`);
  }
});
