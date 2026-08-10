"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const core = require("./no-show-settlement-core");

function fixture(overrides = {}) {
  return {
    delivery: {senderId: "sender-a", paymentSessionId: "session-a", stripePaymentIntentId: "pi-a", paidAmount: 15, paymentStatus: "paid", remainingAmount: 15},
    paymentSession: {userId: "sender-a", stripePaymentIntentId: "pi-a"},
    paymentIntent: {id: "pi-a", status: "succeeded", metadata: {userId: "sender-a", paymentSessionId: "session-a"}},
    ...overrides,
  };
}

test("no-show amounts preserve collect-first policy", () => {
  assert.deepEqual(core.AMOUNTS, {customerPence: 700, riderPence: 400, platformPence: 300});
  assert.deepEqual(core.pendingFinancial("delivery-a", "rider-a"), {
    settlementId: "no_show_delivery-a", idempotencyKey: "no_show_settlement_delivery-a",
    deliveryId: "delivery-a", riderId: "rider-a", state: "SETTLEMENT_PENDING",
    settlementStatus: "pending_collection", customerCharge: 7, riderCompensation: 4,
    platformAmount: 3, customerCollected: 0, riderCredited: 0, platformRealized: 0, additionalCustomerCharge: 0,
    attemptCount: 0,
  });
});

test("no-show retries use bounded backoff and exhaust after five attempts", () => {
  const now = Date.UTC(2026, 7, 10);
  assert.equal(core.retryDecision(1, now).nextAttemptAt.getTime(), now + 5 * 60 * 1000);
  assert.equal(core.retryDecision(4, now).nextAttemptAt.getTime(), now + 240 * 60 * 1000);
  assert.deepEqual(core.retryDecision(5, now), {exhausted: true, nextAttemptAt: null});
});

test("delivery-bound existing payment authority is accepted without a new charge", () => {
  assert.equal(core.authorityDecision(fixture()).allowed, true);
  const rothOnly = fixture({
    delivery: {senderId: "sender-a", paymentSessionId: "session-a", paidAmount: 12, paymentStatus: "paid", remainingAmount: 0, rothAppliedAmount: 12},
    paymentSession: {userId: "sender-a"}, paymentIntent: {},
  });
  assert.equal(core.authorityDecision(rothOnly).allowed, true);
});

test("legacy or mismatched authority fails closed", () => {
  const legacy = fixture();
  legacy.delivery.paidAmount = 6.99;
  assert.equal(core.authorityDecision(legacy).reason, "paid_amount_insufficient");
  const wrongSender = fixture();
  wrongSender.paymentIntent.metadata.userId = "sender-b";
  assert.equal(core.authorityDecision(wrongSender).reason, "payment_authority_mismatch");
});
