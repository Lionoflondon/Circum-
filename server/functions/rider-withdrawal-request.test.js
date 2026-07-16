const assert = require("node:assert/strict");
const test = require("node:test");

const {riderWithdrawalFailure} = require("./rider-connect");

const valid = {
  amount: 25,
  available: 80,
  minimum: 5,
  existingStatus: "completed",
  approvedRider: true,
  stripeReady: true,
  payoutPaused: false,
};

test("approved Stripe-ready rider can request available cash", () => {
  assert.equal(riderWithdrawalFailure(valid), null);
});

test("duplicate pending withdrawal is blocked", () => {
  assert.equal(
      riderWithdrawalFailure({...valid, existingStatus: "processing"}),
      "duplicate_pending",
  );
});

test("withdrawal cannot exceed available cash", () => {
  assert.equal(
      riderWithdrawalFailure({...valid, amount: 81}),
      "exceeds_available",
  );
});

test("Roth or unavailable funds cannot be represented as cash", () => {
  assert.equal(
      riderWithdrawalFailure({...valid, available: 0}),
      "exceeds_available",
  );
});

test("unapproved or Stripe-incomplete riders are blocked", () => {
  assert.equal(
      riderWithdrawalFailure({...valid, approvedRider: false}),
      "approval_required",
  );
  assert.equal(
      riderWithdrawalFailure({...valid, stripeReady: false}),
      "stripe_not_ready",
  );
});
