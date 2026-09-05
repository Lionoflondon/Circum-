/* eslint-disable max-len */
const test = require("node:test");
const assert = require("node:assert/strict");
const {reconcileStripeCancellation, authoritativePaymentBreakdown} = require("./delivery-policy")._test;

function settlement(overrides = {}) {
  return {deliveryId: "delivery-1", senderId: "sender-1", stripePaymentIntentId: "pi_1",
    breakdown: {stripePaid: 13, stripeRefund: 10, rothPaid: 7, rothRestoration: 7}, ...overrides};
}
function stripeFor(overrides = {}, {refundError = null, refundStatus = "succeeded", refunds = []} = {}) {
  let intent = {id: "pi_1", amount: 1300, amount_received: 1300, currency: "gbp",
    status: "succeeded", metadata: {userId: "sender-1"}, ...overrides};
  const calls = {refunds: [], captures: [], cancels: []};
  const history = [...refunds];
  return {calls, history,
    paymentIntents: {
      retrieve: async () => intent,
      capture: async (...args) => {
        calls.captures.push(args);
        intent = {...intent, status: "succeeded", amount_received: args[1].amount_to_capture};
        return intent;
      },
      cancel: async (...args) => {
        calls.cancels.push(args);
        intent = {...intent, status: "canceled"};
        return intent;
      },
    },
    refunds: {
      list: async () => ({data: history, has_more: false}),
      create: async (...args) => {
        calls.refunds.push(args);
        if (refundError) throw refundError;
        const refund = {id: `re_${history.length}`, amount: args[0].amount, status: refundStatus};
        history.push(refund);
        return refund;
      },
    },
  };
}

test("canonical mixed refund returns £10 Stripe and repeats without another refund", async () => {
  const stripe = stripeFor();
  assert.equal((await reconcileStripeCancellation(stripe, settlement())).refundedPence, 1000);
  assert.equal((await reconcileStripeCancellation(stripe, settlement())).status, "already_refunded");
  assert.equal(stripe.calls.refunds.length, 1);
  assert.equal(stripe.calls.refunds[0][0].amount, 1000);
});
test("partial prior refund refunds only the difference; full prior refund is idempotent", async () => {
  for (const prior of [400, 1000]) {
    const stripe = stripeFor({}, {refunds: [{id: "prior", amount: prior, status: "succeeded"}]});
    await reconcileStripeCancellation(stripe, settlement());
    assert.equal(stripe.calls.refunds.length, prior === 1000 ? 0 : 1);
    if (prior < 1000) assert.equal(stripe.calls.refunds[0][0].amount, 600);
  }
});
test("Stripe timeout retries with the identical idempotency key", async () => {
  const stripe = stripeFor({}, {refundError: new Error("timeout")});
  for (let i = 0; i < 2; i++) await assert.rejects(() => reconcileStripeCancellation(stripe, settlement()), /timeout/);
  assert.equal(stripe.calls.refunds[0][2], undefined);
  assert.equal(stripe.calls.refunds[0][1].idempotencyKey, stripe.calls.refunds[1][1].idempotencyKey);
});
test("pending refund never reports settlement and never issues a second refund", async () => {
  const stripe = stripeFor({}, {refundStatus: "pending"});
  await assert.rejects(() => reconcileStripeCancellation(stripe, settlement()), /pending/);
  await assert.rejects(() => reconcileStripeCancellation(stripe, settlement()), /pending/);
  assert.equal(stripe.calls.refunds.length, 1);
  stripe.history[0].status = "succeeded";
  await reconcileStripeCancellation(stripe, settlement());
  assert.equal(stripe.calls.refunds.length, 1);
});
test("failed prior refunds are retried with a new idempotency key", async () => {
  const stripe = stripeFor({}, {refundStatus: "failed"});
  await assert.rejects(() => reconcileStripeCancellation(stripe, settlement()), /failed/);
  await assert.rejects(() => reconcileStripeCancellation(stripe, settlement()), /failed/);
  assert.notEqual(stripe.calls.refunds[0][1].idempotencyKey, stripe.calls.refunds[1][1].idempotencyKey);
});
test("partial capture releases £10; a retry does not refund the retained £3", async () => {
  const stripe = stripeFor({status: "requires_capture", amount_received: 0});
  await reconcileStripeCancellation(stripe, settlement());
  await reconcileStripeCancellation(stripe, settlement());
  assert.equal(stripe.calls.captures.length, 1);
  assert.equal(stripe.calls.captures[0][1].amount_to_capture, 300);
  assert.equal(stripe.calls.refunds.length, 0);
});
test("free cancellation releases an authorization idempotently", async () => {
  const stripe = stripeFor({status: "requires_capture", amount_received: 0});
  const value = settlement({breakdown: {stripePaid: 13, stripeRefund: 13}});
  await reconcileStripeCancellation(stripe, value);
  await reconcileStripeCancellation(stripe, value);
  assert.equal(stripe.calls.cancels.length, 1);
  assert.equal(stripe.calls.refunds.length, 0);
});
test("zero Stripe refund retains the contribution; Roth-only never calls Stripe", async () => {
  const stripe = stripeFor();
  await reconcileStripeCancellation(stripe, settlement({breakdown: {stripePaid: 13, stripeRefund: 0}}));
  assert.equal(stripe.calls.refunds.length, 0);
  await reconcileStripeCancellation({}, settlement({breakdown: {stripePaid: 0, stripeRefund: 0}}));
});
test("corrupt ownership, currency, funding or excess prior refunds fail closed", async () => {
  for (const overrides of [{metadata: {}}, {metadata: {userId: "other"}}, {amount: 1200}, {currency: "usd"}, {amount_received: 200}]) {
    const stripe = stripeFor(overrides);
    await assert.rejects(() => reconcileStripeCancellation(stripe, settlement()));
    assert.equal(stripe.calls.refunds.length, 0);
  }
  await assert.rejects(() => reconcileStripeCancellation(
      stripeFor({}, {refunds: [{id: "prior", amount: 1100, status: "succeeded"}]}), settlement()), /excess/);
  await assert.rejects(() => reconcileStripeCancellation(stripeFor({status: "requires_confirmation"}), settlement()), /Unfunded/);
});
test("funding comes from payment session and verified Roth debit, never editable delivery totals", async () => {
  const records = {
    "senderPaymentSessions/session-1": {userId: "sender-1", currency: "GBP", amountDue: 20,
      rothAppliedAmount: 7, remainingAmount: 13, stripePaymentIntentId: "pi_1"},
    "walletTransactions/wallet_delivery_session-1": {uid: "sender-1", status: "completed",
      relatedEntityId: "delivery-1", amount: -7, balanceType: "rothCredit", userEmail: "sender@example.com"},
  };
  const db = {collection: (name) => ({doc: (id) => `${name}/${id}`})};
  const tx = {get: async (path) => ({exists: !!records[path], data: () => records[path]})};
  const delivery = {id: "delivery-1", senderId: "sender-1", paymentSessionId: "session-1", stripePaymentIntentId: "pi_1", price: 9999, rothAppliedAmount: 9999};
  const result = await authoritativePaymentBreakdown(tx, db, delivery);
  assert.equal(result.grossDeliveryTotal, 20);
  assert.equal(result.rothPaid, 7);
  records["walletTransactions/wallet_delivery_session-1"].uid = "other";
  await assert.rejects(() => authoritativePaymentBreakdown(tx, db, delivery));
});
