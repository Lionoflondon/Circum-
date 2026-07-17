const test = require("node:test");
const assert = require("node:assert/strict");

const {
  estimateStripeFee,
  riderWithdrawalFailure,
  resolveRiderPayoutBreakdown,
  stripeStatusFromAccount,
} = require("./rider-connect");

test("deducts Stripe payout fees from rider share", () => {
  const breakdown = resolveRiderPayoutBreakdown({
    totalCustomerPaid: 20,
    circumPlatformCommission: 7,
    riderGrossShare: 13,
  });

  assert.equal(breakdown.totalCustomerPaid, 20);
  assert.equal(breakdown.circumPlatformCommission, 7);
  assert.equal(breakdown.riderGrossShare, 13);
  assert.equal(breakdown.stripeFeeDeductedFromRider, 0.4);
  assert.equal(breakdown.riderNetPayout, 12.6);
  assert.equal(breakdown.payoutFeePayer, "rider");
});

test("derives Circum commission without reducing it for Stripe fees", () => {
  const breakdown = resolveRiderPayoutBreakdown({
    totalCustomerPaid: 30,
    riderGrossShare: 18,
  });

  assert.equal(breakdown.circumPlatformCommission, 12);
  assert.equal(breakdown.stripeFeeDeductedFromRider, 0.47);
  assert.equal(breakdown.riderNetPayout, 17.53);
});

test("blocks payout when estimated fees exceed rider share", () => {
  const breakdown = resolveRiderPayoutBreakdown({
    totalCustomerPaid: 0.3,
    circumPlatformCommission: 0,
    riderGrossShare: 0.1,
  });

  assert.equal(breakdown.riderNetPayout, -0.11);
  assert.equal(breakdown.adminReviewRequired, true);
});

test("estimates Stripe fee from backend policy values", () => {
  const fee = estimateStripeFee(100, {
    percentBps: 150,
    fixedPence: 20,
    minimumPence: 0,
  });

  assert.equal(fee, 1.7);
});

test("maps enabled Express account to payouts_enabled", () => {
  const status = stripeStatusFromAccount({
    id: "acct_enabled",
    details_submitted: true,
    charges_enabled: true,
    payouts_enabled: true,
    requirements: {currently_due: [], past_due: []},
  });

  assert.equal(status, "payouts_enabled");
});

test("maps incomplete Express account to onboarding", () => {
  const status = stripeStatusFromAccount({
    id: "acct_onboarding",
    details_submitted: false,
    charges_enabled: false,
    payouts_enabled: false,
    requirements: {currently_due: [], past_due: []},
  });

  assert.equal(status, "onboarding");
});

test("maps requirements to action_required", () => {
  const status = stripeStatusFromAccount({
    id: "acct_action",
    details_submitted: true,
    charges_enabled: true,
    payouts_enabled: false,
    requirements: {currently_due: ["external_account"], past_due: []},
  });

  assert.equal(status, "action_required");
});

test("rider withdrawal policy is backend-authoritative", () => {
  const base = {
    amount: 25,
    available: 100,
    minimum: 1,
    existingStatus: "",
    approvedRider: true,
    stripeReady: true,
    payoutPaused: false,
  };

  assert.equal(riderWithdrawalFailure(base), null);
  assert.equal(
      riderWithdrawalFailure({...base, approvedRider: false}),
      "approval_required",
  );
  assert.equal(
      riderWithdrawalFailure({...base, stripeReady: false}),
      "stripe_not_ready",
  );
  assert.equal(
      riderWithdrawalFailure({...base, payoutPaused: true}),
      "stripe_not_ready",
  );
  assert.equal(
      riderWithdrawalFailure({...base, existingStatus: "requested"}),
      "duplicate_pending",
  );
  assert.equal(
      riderWithdrawalFailure({...base, existingStatus: "processing"}),
      "duplicate_pending",
  );
  assert.equal(riderWithdrawalFailure({...base, amount: 0}), "invalid_amount");
  assert.equal(riderWithdrawalFailure({...base, amount: 0.5}), "below_minimum");
  assert.equal(
      riderWithdrawalFailure({...base, amount: 101}),
      "exceeds_available",
  );
});
