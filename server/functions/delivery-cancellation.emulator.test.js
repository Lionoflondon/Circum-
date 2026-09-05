/* eslint-disable max-len */
const {test, before, after, mock} = require("node:test");
const assert = require("node:assert/strict");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {getAuth} = require("firebase-admin/auth");
const {walletIdForEmail} = require("./wallet-core");
const policy = require("./delivery-policy");
const ledger = require("./roth-ledger");
const communications = require("./communication-engine");
const enabled = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
let app; let db; let sequence = 0;
before(() => {
  if (!enabled) return;
  app = initializeApp({projectId: "demo-cancellation"}); db = getFirestore();
  db.settings({ignoreUndefinedProperties: true});
  mock.method(getAuth(), "getUserByEmail", async (email) => ({uid: email.split("@")[0], email}));
});
after(async () => {
 mock.restoreAll(); if (app) await deleteApp(app);
});
async function fixture({roth = 7, stripe = 13, state = "accepted", late = false} = {}) {
  const id = `cancellation-${++sequence}`; const uid = `sender-${sequence}`; const email = `${uid}@example.com`;
  const rider = `rider-${sequence}`; const session = `session-${sequence}`;
  const delivery = {senderId: uid, userId: uid, riderId: rider, status: state, state,
    paymentSessionId: session, stripePaymentIntentId: stripe > 0 ? `pi_${sequence}` : null,
    arrivedAt: state === "arrived_at_pickup" ? Date.now() - (late ? 240000 : 1000) : null};
  await db.collection("deliveryRequests").doc(id).set(delivery);
  await db.collection("senderPaymentSessions").doc(session).set({userId: uid, userEmail: email,
    amountDue: roth + stripe, remainingAmount: stripe, rothAppliedAmount: roth,
    currency: "GBP", paymentStatus: "paid", stripePaymentIntentId: delivery.stripePaymentIntentId, deliveryId: id});
  await db.collection("wallets").doc(walletIdForEmail(email)).set({balance: 50, rothCredit: 50, uid});
  if (roth > 0) {
await db.collection("walletTransactions").doc(`wallet_delivery_${session}`).set({
    uid, userEmail: email, amount: -roth, status: "completed", relatedEntityId: id, balanceType: "rothCredit"});
}
  for (const collection of ["riderPresence", "riders", "riderProfiles"]) {
    await db.collection(collection).doc(rider).set({activeDeliveryId: id, busy: true});
  }
  const context = {auth: {uid, token: {email}}, app: {appId: "test"}};
  const refunds = []; const keys = new Map(); let fail = false;
  const client = {paymentIntents: {retrieve: async () => {
    if (fail) throw new Error("Stripe 503 timeout");
    return {id: delivery.stripePaymentIntentId, amount: stripe * 100, amount_received: stripe * 100,
      currency: "gbp", status: "succeeded", metadata: {userId: uid, paymentSessionId: session}};
  }}, refunds: {
    list: async () => ({data: refunds, has_more: false}),
    create: async (data, options) => {
      if (!keys.has(options.idempotencyKey)) {
        const refund = {id: `refund-${refunds.length}`, amount: data.amount, status: "succeeded"};
        keys.set(options.idempotencyKey, refund); refunds.push(refund);
      }
      return keys.get(options.idempotencyKey);
    },
  }};
  const quote = await policy.previewSenderCancellation.run({deliveryId: id}, context);
  const cancel = () => policy.requestSenderCancellation(client).run({deliveryId: id, quoteToken: quote.quoteToken}, context);
  return {id, uid, email, rider, client, refunds, cancel, quote, context, fail: (value) => {
fail = value;
}};
}

test("actual transactions reconcile all stages and funding sources exactly once", {skip: !enabled}, async () => {
  for (const item of [
    {roth: 0, stripe: 20, state: "requested", fee: 0},
    {roth: 20, stripe: 0, state: "requested", fee: 0},
    {roth: 7, stripe: 13, state: "requested", fee: 0},
    {roth: 7, stripe: 13, state: "accepted", fee: 3},
    {roth: 7, stripe: 13, state: "arrived_at_pickup", fee: 5},
    {roth: 7, stripe: 13, state: "arrived_at_pickup", late: true, fee: 7},
    {roth: 18, stripe: 2, state: "arrived_at_pickup", late: true, fee: 7},
    {roth: 20, stripe: 0, state: "accepted", fee: 3},
    {roth: 0, stripe: 3, state: "accepted", fee: 3},
  ]) {
    const f = await fixture(item);
    const result = await f.cancel();
    assert.equal(result.success, true);
    await f.cancel();
    const b = result.breakdown;
    assert.equal(b.cancellationFee, item.fee);
    assert.equal(Math.round((b.stripeRefund + b.rothRestoration) * 100), Math.round((item.stripe + item.roth - item.fee) * 100));
    assert.ok(b.stripeRefund <= item.stripe && b.rothRestoration <= item.roth);
    assert.equal(b.riderCompensation + b.circumRetained, item.fee);
    assert.equal(f.refunds.reduce((sum, value) => sum + value.amount, 0), b.stripeRefund * 100);
    const wallet = await db.collection("wallets").doc(walletIdForEmail(f.email)).get();
    assert.equal(wallet.data().balance, 50 + b.rothRestoration);
    const earnings = await db.collection("riderEarningTransactions").where("deliveryId", "==", f.id).get();
    assert.equal(earnings.size, item.fee ? 1 : 0);
    if (item.fee) assert.equal((await db.collection("riderEarnings").doc(f.rider).get()).data().availableBalance, b.riderCompensation);
    assert.equal((await db.collection("deliveryRequests").doc(f.id).get()).data().cancellationSettlementStatus, "settled");
  }
});
test("Stripe and Roth failures remain pending and scheduler resumes without double refund", {skip: !enabled}, async () => {
  const f = await fixture(); f.fail(true);
  await assert.rejects(f.cancel, /reconciled/);
  let delivery = (await db.collection("deliveryRequests").doc(f.id).get()).data();
  assert.equal(delivery.status, "accepted"); assert.equal(delivery.matchingStatus, "blocked");
  assert.equal((await db.collection("wallets").doc(walletIdForEmail(f.email)).get()).data().balance, 50);
  f.fail(false);
  const original = ledger.recordRothMovement;
  ledger.recordRothMovement = async () => {
throw new Error("Roth transient failure");
};
  try {
await assert.rejects(f.cancel, /reconciled/);
} finally {
ledger.recordRothMovement = original;
}
  assert.equal(f.refunds.length, 1);
  await policy.reconcilePendingSenderCancellations(f.client).run({});
  delivery = (await db.collection("deliveryRequests").doc(f.id).get()).data();
  assert.equal(delivery.status, "cancelled_by_sender"); assert.equal(f.refunds.length, 1);
  assert.equal((await db.collection("wallets").doc(walletIdForEmail(f.email)).get()).data().balance, 57);
});
test("notification failure recovers after settlement without repeating financial effects", {skip: !enabled}, async () => {
  const f = await fixture(); const original = communications.emitNotification;
  communications.emitNotification = async () => {
throw new Error("notification failure");
};
  try {
assert.equal((await f.cancel()).notificationsComplete, false);
} finally {
communications.emitNotification = original;
}
  await f.cancel();
  assert.equal((await db.collection("deliveryCancellationSettlements").doc(f.id).get()).data().notificationStatus, "completed");
  assert.equal(f.refunds.length, 1);
  assert.equal((await db.collection("wallets").doc(walletIdForEmail(f.email)).get()).data().balance, 57);
});
test("concurrent requests preserve one refund, restoration and compensation", {skip: !enabled}, async () => {
  const f = await fixture();
  await Promise.allSettled([f.cancel(), f.cancel(), f.cancel()]);
  await f.cancel();
  assert.equal(f.refunds.length, 1);
  assert.equal((await db.collection("wallets").doc(walletIdForEmail(f.email)).get()).data().balance, 57);
  assert.equal((await db.collection("riderEarningTransactions").where("deliveryId", "==", f.id).get()).size, 1);
});
test("foreign caller and stale disclosure cannot reserve cancellation or refund", {skip: !enabled}, async () => {
  const f = await fixture({state: "requested"});
  await assert.rejects(() => policy.requestSenderCancellation(f.client).run({deliveryId: f.id}, {auth: {uid: "foreign"}}), /sender/);
  await db.collection("deliveryRequests").doc(f.id).update({state: "accepted", status: "accepted"});
  const result = await f.cancel(); assert.equal(result.success, false);
  assert.equal((await db.collection("deliveryCancellationSettlements").doc(f.id).get()).exists, false);
  assert.equal(f.refunds.length, 0);
});
test("sender cannot edit allocation, fee stage or settlement authority through Firestore", {skip: !enabled}, async () => {
  const {initializeTestEnvironment, assertFails, assertSucceeds} = require("@firebase/rules-unit-testing");
  const {doc, updateDoc, setDoc} = require("firebase/firestore");
  const fs = require("node:fs"); const path = require("node:path");
  const env = await initializeTestEnvironment({projectId: "demo-cancellation", firestore: {
    rules: fs.readFileSync(path.join(__dirname, "../../firestore.rules"), "utf8"),
  }});
  try {
    const f = await fixture(); const client = env.authenticatedContext(f.uid, {role: "sender", adminRole: "", roles: [], admin: false, super_admin: false}).firestore();
    await assertSucceeds(updateDoc(doc(client, "deliveryRequests", f.id), {senderNote: "safe note"}));
    for (const field of ["state", "price", "rothAppliedAmount", "remainingAmount", "cancellationSettlementStatus", "arrivedAt", "senderId", "riderId"]) {
      await assertFails(updateDoc(doc(client, "deliveryRequests", f.id), {[field]: "tampered"}));
    }
    await assertFails(setDoc(doc(client, "deliveryCancellationSettlements", f.id), {status: "settled"}));
  } finally {
await env.cleanup();
}
});

test("pending cancellation blocks Rider lifecycle and no-show; finalization preserves a new assignment", {skip: !enabled}, async () => {
  const f = await fixture(); f.fail(true);
  await assert.rejects(f.cancel);
  const tracking = require("./delivery-tracking");
  await assert.rejects(() => tracking.updateDeliveryTrackingStatus.run(
      {deliveryId: f.id, action: "confirm_collected"}, {auth: {uid: f.rider}}), /paused/);
  await assert.rejects(() => policy.markRiderNoShow.run(
      {deliveryId: f.id}, {auth: {uid: f.rider}}), /paused/);
  for (const collection of ["riderPresence", "riders", "riderProfiles"]) {
    await db.collection(collection).doc(f.rider).update({activeDeliveryId: "another-delivery"});
  }
  f.fail(false); await f.cancel();
  assert.equal((await db.collection("riderPresence").doc(f.rider).get()).data().activeDeliveryId, "another-delivery");
  await assert.rejects(() => policy.markRiderNoShow.run(
      {deliveryId: f.id}, {auth: {uid: f.rider}}), /paused/);
});
