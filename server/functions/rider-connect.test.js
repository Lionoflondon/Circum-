const test = require("node:test");
const assert = require("node:assert/strict");

const {
  estimateStripeFee,
  resolveRiderPayoutBreakdown,
} = require("./rider-connect");

test("deducts Stripe payout fees from rider share, not Circum commission", () => {
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

test("blocks payout for admin review when estimated fees exceed rider share", () => {
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
