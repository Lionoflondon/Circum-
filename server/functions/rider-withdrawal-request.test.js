const assert = require("node:assert/strict");
const test = require("node:test");

const fs = require("node:fs");
const {
  isActiveRiderPayoutStatus,
  riderWithdrawalFailure,
} = require("./rider-connect");

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

test("only real Stripe lifecycle states block another payout", () => {
  for (const status of ["requested", "pending", "reserved", "processing", "scheduled"]) {
    assert.equal(isActiveRiderPayoutStatus(status), true);
  }
  for (const status of ["approved", "paid", "failed", "cancelled", "rejected"]) {
    assert.equal(isActiveRiderPayoutStatus(status), false);
  }
});

test("Rider request reserves a unique operation and invokes Stripe itself", () => {
  const source = fs.readFileSync("rider-connect.js", "utf8");
  const index = fs.readFileSync("index.js", "utf8");
  const start = source.indexOf("function requestRiderWithdrawal(stripeOrFactory)");
  const end = source.indexOf("function cancelRiderWithdrawal()", start);
  const request = source.slice(start, end);

  assert.match(request, /stripeSecretRuntime\.https\.onCall/);
  assert.match(request, /requestRef = db\.collection\("payoutRequests"\)\.doc\(\)/);
  assert.match(source, /collection\("riderPayoutLocks"\)\.doc\(riderId\)/);
  assert.match(request, /requestSource: "rider_app"/);
  assert.match(request, /executeRiderTransferOrPayout\(\{/);
  assert.match(request, /actorType: "rider"/);
  assert.doesNotMatch(request, /doc\(`active_\$\{riderId\}`\)/);
  assert.match(index, /requestRiderWithdrawal\(stripeConnectClient\)/);
});

test("all payout entry points share the same active-request lock", () => {
  const source = fs.readFileSync("rider-connect.js", "utf8");
  assert.match(source, /lockData\.active === true && lockedRequestId/);
  assert.match(source, /lockedRequestId !== requestRef\.id/);
  assert.match(source, /activeRequestId: requestRef\.id/);
});

test("reserved payouts have a bounded idempotent recovery path", () => {
  const source = fs.readFileSync("rider-connect.js", "utf8");
  const index = fs.readFileSync("index.js", "utf8");
  assert.match(source, /function scheduledRiderPayoutRecovery\(stripeOrFactory\)/);
  assert.match(source, /\.where\("status", "in", \["reserved", "processing"\]\)/);
  assert.match(source, /\.limit\(25\)/);
  assert.match(source, /payout\.fundsReserved !== true/);
  assert.match(source, /requestId: doc\.id/);
  assert.match(source, /executeRiderTransferOrPayout\(\{/);
  assert.match(index, /scheduledRiderPayoutRecovery\(stripeConnectClient\)/);
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
