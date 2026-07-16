/* eslint-disable max-len */
const test = require("node:test");
const assert = require("node:assert/strict");
const {refundPatch} = require("./stripe-refunds");

test("partial refunds remain distinct from full refunds", () => {
  const patch = refundPatch({amount: 1000, amount_refunded: 400, refunded: false, currency: "gbp", refunds: {data: [{id: "re_partial", created: 1}]}});
  assert.equal(patch.refundStatus, "partially_refunded");
  assert.equal(patch.refunded, false);
  assert.equal(patch.refundedAmount, 400);
  assert.equal(patch.stripeRefundId, "re_partial");
});

test("full refunds set loyalty-compatible fields", () => {
  const patch = refundPatch({amount: 1000, amount_refunded: 1000, refunded: true, currency: "gbp", refunds: {data: [{id: "re_full", created: 1}]}});
  assert.equal(patch.refundStatus, "refunded");
  assert.equal(patch.refunded, true);
});
