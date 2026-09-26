"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const policy = require("./gift-communications-policy");

test("canonical Gifts matrix explicitly classifies consequential, push-only, and non-applicable events", () => {
  assert.deepEqual(policy.COMMUNICATION_POLICY[policy.EVENT.PAYMENT_CONFIRMED], {classification: "sender_email", recipients: ["sender"], source: "giftRequests"});
  assert.equal(policy.COMMUNICATION_POLICY[policy.EVENT.PAYMENT_PROBLEM].classification, "sender_email");
  assert.equal(policy.COMMUNICATION_POLICY[policy.EVENT.STORY_READY].classification, "sender_and_recipient_email");
  for (const event of [policy.EVENT.SUBMITTED, policy.EVENT.CURATION_STARTED, policy.EVENT.DELIVERY_PROGRESS]) {
    assert.equal(policy.COMMUNICATION_POLICY[event].classification, "push_only");
  }
  assert.equal(policy.COMMUNICATION_POLICY[policy.EVENT.REFUND].classification, "not_applicable");
});

test("prospective event checks use business timestamps, not later maintenance updates", () => {
  const effectiveAt = "2026-09-26T12:00:00.000Z";
  assert.equal(policy.eventIsPostPolicy({approvedAt: "2026-09-26T12:00:01.000Z", updatedAt: "2026-09-27T12:00:00.000Z"}, policy.EVENT.APPROVED, effectiveAt), true);
  assert.equal(policy.eventIsPostPolicy({approvedAt: "2026-09-25T12:00:01.000Z", updatedAt: "2026-09-27T12:00:00.000Z"}, policy.EVENT.APPROVED, effectiveAt), false);
  assert.equal(policy.eventIsPostPolicy({updatedAt: "2026-09-27T12:00:00.000Z"}, policy.EVENT.APPROVED, effectiveAt), false);
});

test("payment problem classification is neutral when a charge may have succeeded", () => {
  assert.equal(policy.paymentProblemKind({paymentStatus: "failed"}), "failed");
  assert.equal(policy.paymentProblemKind({paymentStatus: "requires_action"}), "unconfirmed");
  assert.equal(policy.paymentProblemKind({paymentStatus: "failed", amountReceivedPence: 5000}), "unconfirmed");
  assert.equal(policy.isPaymentProblemState({paymentStatus: "paid"}), false);
  assert.equal(policy.isPaymentProblemState({paymentStatus: "requires_payment_method"}), true);
});
