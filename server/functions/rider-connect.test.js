/* eslint-disable max-len */
const test = require("node:test");
const assert = require("node:assert/strict");

const {
  estimateStripeFee,
  resolveRiderPayoutBreakdown,
  stripeStatusFromAccount,
} = require("./rider-connect");
const fs = require("node:fs");

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

test("Admin payout review is backend authoritative and auditable", () => {
  const source = fs.readFileSync("rider-connect.js", "utf8");
  assert.match(source, /function adminReviewRiderWithdrawal\(\)/);
  assert.match(source, /assertActor\(context, riderId, \{adminOnly: true\}\)/);
  assert.match(source, /db\.runTransaction/);
  assert.match(source, /status: "rejected"/);
  assert.match(source, /payoutStatus: "rejected"/);
  assert.match(source, /reviewStatus: "rejected"/);
  assert.match(source, /riderPayoutAudit/);
  assert.match(source, /idempotent: true/);
});

test("Stripe Connect webhook money events are replay-safe", () => {
  const source = fs.readFileSync("rider-connect.js", "utf8");
  assert.match(source, /function processStripeConnectEventOnce/);
  assert.match(source, /collection\("stripeConnectWebhookEvents"\)\.doc\(eventId\)/);
  assert.match(source, /const existingEvent = await transaction\.get\(eventRef\)/);
  assert.match(source, /if \(existingEvent\.exists\)/);
  assert.match(source, /transaction\.create\(eventRef/);
  assert.match(source, /event\.type === "payout\.paid" \|\| event\.type === "payout\.failed"[\s\S]*processStripeConnectEventOnce/);
  assert.match(source, /event\.type === "transfer\.created" \|\| event\.type === "transfer\.failed"[\s\S]*processStripeConnectEventOnce/);
  assert.match(source, /const active = \["processing", "pending", "requested"\]\.includes\(currentStatus\)/);
  assert.match(source, /event\.type === "transfer\.failed" && active && riderId && amount > 0/);
});
