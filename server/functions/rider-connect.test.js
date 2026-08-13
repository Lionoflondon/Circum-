/* eslint-disable max-len */
const test = require("node:test");
const assert = require("node:assert/strict");

const {
  estimateStripeFee,
  resolveRiderPayoutBreakdown,
  stripeStatusFromAccount,
  computeRiderPayoutReadiness,
  availableRiderCash,
  isIndeterminateStripeTransferError,
} = require("./rider-connect");
const fs = require("node:fs");
const {
  requiredDocumentIds,
  payoutReadiness,
  canTransitionApplication,
} = require("./rider-certification-policy");

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

test("£2 payout amount is distinct from its processing cost", () => {
  const breakdown = resolveRiderPayoutBreakdown({riderGrossShare: 2});
  assert.equal(breakdown.riderGrossShare, 2);
  assert.equal(breakdown.stripeFeeDeductedFromRider, 0.23);
  assert.equal(breakdown.riderNetPayout, 1.77);
});

test("ambiguous Stripe transfer errors retain funds for confirmation", () => {
  assert.equal(isIndeterminateStripeTransferError({
    type: "StripeConnectionError",
    code: "ETIMEDOUT",
  }), true);
  assert.equal(isIndeterminateStripeTransferError({
    type: "StripeAPIError",
    statusCode: 500,
  }), true);
  assert.equal(isIndeterminateStripeTransferError({
    type: "StripeInvalidRequestError",
    statusCode: 400,
  }), false);
  assert.equal(isIndeterminateStripeTransferError({
    type: "StripeAuthenticationError",
    statusCode: 401,
  }), false);
});

test("canonical zero cash never falls through to stale legacy balances", () => {
  assert.equal(availableRiderCash({
    availableBalance: 0,
    availableEarnings: 99,
    accountBalance: 99,
  }), 0);
  assert.equal(availableRiderCash({availableEarnings: 12.34}), 12.34);
});

test("Rider payout quote is read-only, authenticated and App Check protected", () => {
  const source = fs.readFileSync("rider-connect.js", "utf8");
  const index = fs.readFileSync("index.js", "utf8");
  const start = source.indexOf("function getRiderPayoutQuote()");
  const end = source.indexOf("async function processStripeConnectEventOnce", start);
  const quote = source.slice(start, end);

  assert.match(quote, /firstPartyCallableRuntime\.https\.onCall/);
  assert.match(quote, /await assertActor\(context, riderId\)/);
  assert.match(quote, /resolveRiderPayoutBreakdown\(\{riderGrossShare: amount\}\)/);
  assert.match(quote, /processingCost: breakdown\.stripeFeeDeductedFromRider/);
  assert.match(quote, /bankReceives: breakdown\.riderNetPayout/);
  assert.doesNotMatch(quote, /\.set\(|\.update\(|\.create\(/);
  assert.match(index, /exports\.getRiderPayoutQuote = riderConnect\.getRiderPayoutQuote\(\);/);
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
  assert.match(source, /event\.type === "payout\.created"[\s\S]*event\.type === "payout\.paid"[\s\S]*event\.type === "payout\.failed"[\s\S]*event\.type === "payout\.canceled"[\s\S]*processStripeConnectEventOnce/);
  assert.match(source, /event\.type === "transfer\.created" \|\| event\.type === "transfer\.failed"[\s\S]*processStripeConnectEventOnce/);
  assert.match(source, /const active = isActiveRiderPayoutStatus\(currentStatus\)/);
  assert.match(source, /event\.type === "transfer\.failed" && active && riderId && amount > 0/);
});

test("Rider payout transfer uses Stripe idempotency", () => {
  const source = fs.readFileSync("rider-connect.js", "utf8");
  assert.match(source, /function stripeTransferIdempotencyKey\(requestId\)/);
  assert.match(source, /idempotencyKey: stripeTransferIdempotencyKey\(reservation\.requestId\)/);
  assert.match(source, /existingTransferId/);
  assert.match(source, /\["processing", "scheduled", "paid"\]\.includes\(existingStatus\)/);
  assert.match(source, /idempotent: true/);
  assert.match(source, /type: "payout_reserved"/);
  assert.match(source, /payout_failed_release_/);
  assert.match(source, /enforceAppCheck: true/);
});

test("Rider payout readiness is backend authoritative", () => {
  const source = fs.readFileSync("rider-connect.js", "utf8");
  const index = fs.readFileSync("index.js", "utf8");
  assert.equal(typeof computeRiderPayoutReadiness, "function");
  assert.match(source, /function riderPayoutReadiness\(\)/);
  assert.match(source, /computeRiderPayoutReadiness\(riderId\)/);
  assert.match(index, /exports\.riderPayoutReadiness = riderConnect\.riderPayoutReadiness\(\);/);
  assert.match(source, /payoutReadinessStatus/);
  assert.match(source, /payoutReadinessChecks/);
});

test("Canonical document matrix supports vehicle-specific requirements", () => {
  assert.deepEqual(requiredDocumentIds("motorbike"), [
    "driving_licence",
    "insurance",
    "registration_v5c",
    "mot",
    "right_to_work",
    "identity",
  ]);
  assert.deepEqual(requiredDocumentIds("electric bike"), [
    "profile_photo",
    "identity",
    "insurance",
    "right_to_work",
  ]);
});

test("Payout readiness requires approval, documents, identity and Stripe status", () => {
  const ready = payoutReadiness({
    vehicleType: "car",
    onboardingStatus: "approved",
    approvalStatus: "approved",
    identityStatus: "approved",
    stripeConnectAccountId: "acct_123",
    stripeDetailsSubmitted: true,
    stripeChargesEnabled: true,
    stripePayoutsEnabled: true,
  }, [
    {type: "driving_licence", status: "approved"},
    {type: "insurance", status: "approved"},
    {type: "registration_v5c", status: "approved"},
    {type: "mot", status: "approved"},
    {type: "right_to_work", status: "approved"},
    {type: "identity", status: "approved"},
  ]);
  assert.equal(ready.ready, true);
  assert.equal(ready.status, "fully_payout_ready");

  const blocked = payoutReadiness({
    vehicleType: "car",
    onboardingStatus: "approved",
    approvalStatus: "approved",
    identityStatus: "approved",
    stripeConnectAccountId: "acct_123",
    stripeDetailsSubmitted: true,
    stripeChargesEnabled: true,
    stripePayoutsEnabled: true,
  }, []);
  assert.equal(blocked.ready, false);
  assert.match(blocked.missingDocuments.join(","), /driving_licence/);
});

test("Rider lifecycle transitions are explicit", () => {
  assert.equal(canTransitionApplication("draft", "submitted"), true);
  assert.equal(canTransitionApplication("submitted", "approved"), false);
  assert.equal(canTransitionApplication("under_review", "approved"), true);
  assert.equal(canTransitionApplication("approved", "draft"), false);
});

test("Stripe transfer is created only after reservation transaction commits", () => {
  const source = fs.readFileSync("rider-connect.js", "utf8");
  const reservationIndex = source.indexOf("const reservation = await db.runTransaction");
  const transferIndex = source.indexOf("transfer = await stripe.transfers.create");
  assert.ok(reservationIndex > -1);
  assert.ok(transferIndex > reservationIndex);
  assert.match(source, /payoutStatus: "reserved"/);
  assert.match(source, /payoutFailureStage: "stripe_transfer"/);
  assert.match(source, /availableBalance: FieldValue\.increment\(reservation\.breakdown\.riderGrossShare\)/);
  assert.match(source, /if \(isIndeterminateStripeTransferError\(error\)\)/);
  assert.match(source, /payoutConfirmationPending: true/);
  assert.match(source, /Your available cash remains protected/);
});

test("Rider payout reservations reconcile pending withdrawals exactly once", () => {
  const source = fs.readFileSync("rider-connect.js", "utf8");
  assert.match(source, /const pendingDelta = requestData\.fundsReserved === true \? 0 : breakdown\.riderGrossShare/);
  assert.match(source, /const availableAfterReservation = roundMoney\(available - pendingDelta\)/);
  assert.match(source, /availableBalance: availableAfterReservation/);
  assert.match(source, /fundsReserved: true/);
  assert.match(source, /const reserved = payout\.fundsReserved === true/);
  assert.match(source, /pendingWithdrawal: reserved \? FieldValue\.increment\(-amount\) : FieldValue\.increment\(0\)/);
  assert.match(source, /const reserved = requestData\.fundsReserved === true/);
  assert.match(source, /fundsReserved: status === "scheduled" \? reserved : false/);
  assert.match(source, /fundsReserved: event\.type === "transfer\.failed" \? false : reserved/);
});

test("Stripe Connect webhook covers payout cancellation and external account updates", () => {
  const source = fs.readFileSync("rider-connect.js", "utf8");
  assert.match(source, /event\.type === "external_account\.updated"/);
  assert.match(source, /stripe\.accounts\.retrieve\(accountId\)/);
  assert.match(source, /stripe_external_account_updated/);
  assert.match(source, /event\.type === "payout\.canceled"/);
  assert.match(source, /const accountId = text\(event\.account \|\| object\.account \|\| object\.destination\)/);
  assert.match(source, /const releaseBalance = status === "failed" \|\| status === "canceled"/);
  assert.match(source, /availableBalance: releaseBalance \? FieldValue\.increment\(amount\) : FieldValue\.increment\(0\)/);
});
