"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const core = require("./no-show-settlement-core");

function fixture(overrides = {}) {
  return {
    delivery: {senderId: "sender-a", paymentSessionId: "session-a", stripePaymentIntentId: "pi-a", stripeCustomerId: "cus-a"},
    paymentSession: {userId: "sender-a", stripePaymentIntentId: "pi-a", stripeCustomerId: "cus-a", futureUsageAuthorized: true},
    paymentIntent: {id: "pi-a", customer: "cus-a", payment_method: "pm-a", metadata: {userId: "sender-a", paymentSessionId: "session-a"}},
    ...overrides,
  };
}

test("no-show amounts preserve collect-first policy", () => {
  assert.deepEqual(core.AMOUNTS, {customerPence: 700, riderPence: 400, platformPence: 300});
  assert.deepEqual(core.pendingFinancial("delivery-a", "rider-a"), {
    settlementId: "no_show_delivery-a", idempotencyKey: "no_show_settlement_delivery-a",
    deliveryId: "delivery-a", riderId: "rider-a", state: "SETTLEMENT_PENDING",
    settlementStatus: "pending_collection", customerCharge: 7, riderCompensation: 4,
    platformAmount: 3, customerCollected: 0, riderCredited: 0, platformRealized: 0,
    attemptCount: 0,
  });
});

test("no-show retries use bounded backoff and exhaust after five attempts", () => {
  const now = Date.UTC(2026, 7, 10);
  assert.equal(core.retryDecision(1, now).nextAttemptAt.getTime(), now + 5 * 60 * 1000);
  assert.equal(core.retryDecision(4, now).nextAttemptAt.getTime(), now + 240 * 60 * 1000);
  assert.deepEqual(core.retryDecision(5, now), {exhausted: true, nextAttemptAt: null});
});

test("explicit, delivery-bound off-session authority is accepted", () => {
  assert.equal(core.authorityDecision(fixture()).allowed, true);
  const input = fixture();
  input.paymentSession.futureUsageAuthorized = false;
  input.paymentIntent.setup_future_usage = "off_session";
  assert.equal(core.authorityDecision(input).allowed, true);
});

test("legacy or mismatched authority fails closed", () => {
  const legacy = fixture();
  legacy.paymentSession.futureUsageAuthorized = false;
  assert.equal(core.authorityDecision(legacy).reason, "off_session_authority_unproven");
  const wrongSender = fixture();
  wrongSender.paymentIntent.metadata.userId = "sender-b";
  assert.equal(core.authorityDecision(wrongSender).reason, "payment_authority_mismatch");
  const wrongCustomer = fixture();
  wrongCustomer.paymentIntent.customer = "cus-b";
  assert.equal(core.authorityDecision(wrongCustomer).reason, "payment_customer_mismatch");
});
