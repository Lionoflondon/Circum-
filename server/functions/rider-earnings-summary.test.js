"use strict";
/* eslint-disable max-len */
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const {reconcileLedger, connectReadiness, materializedSummary} = require("./rider-earnings-summary");

test("positive balance is explicitly unreconciled when categories do not explain it", () => {
  const value = reconcileLedger([], {availableBalance: 1238.40}, []);
  assert.equal(value.reconciled, false); assert.equal(value.unexplained, 1238.40);
});
test("paid historical payout is not active and processing payout is", () => {
  assert.equal(reconcileLedger([], {}, [{status: "paid", amount: 2}]).activePayout, null);
  assert.equal(reconcileLedger([], {}, [{status: "processing", amount: 2}]).activePayout.status, "processing");
});
test("readiness remains separate from withdrawal state", () => {
  assert.equal(connectReadiness({stripeConnectStatus: "pending"}), "pending_verification");
});
test("ledger categories reconcile and duplicate idempotency is counted once", () => {
  const rows = [{type: "delivery_earning", amount: 10, idempotencyKey: "a"}, {type: "delivery_earning", amount: 10, idempotencyKey: "a"}, {type: "tip", amount: 2}, {type: "payout_reserved", amount: 3}, {type: "payout_failed_release", amount: 3}];
  const value = reconcileLedger(rows, {availableBalance: 12}, []); assert.equal(value.calculatedAvailable, 12); assert.equal(value.reconciled, true);
});
test("fixtures are quarantined without deleting ledger money", () => {
  const value=reconcileLedger([{type: "delivery_earning", amount: 50, isTest: true}], {}, []); assert.equal(value.production.length, 0); assert.equal(value.quarantined.length, 1);
});
test("rider earnings default summary uses bounded reads without truncating materialized balances", () => {
  const source = fs.readFileSync("rider-earnings-summary.js", "utf8");
  assert.match(source, /const RECENT_ACTIVITY_LIMIT = 50;/);
  assert.match(source, /return fullReconcile \? query\.get\(\) : query\.limit\(RECENT_ACTIVITY_LIMIT\)\.get\(\);/);
  assert.match(source, /data && data\.fullReconcile === true/);
  assert.match(source, /return materializedSummary\(\{wallet, payouts, recentRows: rows, profile\}\);/);
});

test("materialized summary preserves wallet totals without requiring historical ledger scans", () => {
  const value = materializedSummary({
    wallet: {
      availableBalance: 125,
      pendingBalance: 7,
      deliveryEarningsTotal: 100,
      tipsTotal: 20,
      waitingNoShowTotal: 5,
      completedDeliveries: 4,
    },
    payouts: [{status: "processing", amount: 12}],
    recentRows: [{id: "recent-1"}, {id: "recent-2"}],
    profile: {stripeConnectStatus: "payouts_enabled"},
  });
  assert.equal(value.summaryMode, "materialized");
  assert.equal(value.storedAvailable, 125);
  assert.equal(value.calculatedAvailable, 125);
  assert.equal(value.pending, 7);
  assert.equal(value.reconciled, true);
  assert.equal(value.totals.delivery_earning, 100);
  assert.equal(value.totals.tip, 20);
  assert.equal(value.totals.waiting_fee, 5);
  assert.equal(value.activePayout.status, "processing");
  assert.equal(value.activityCount, 2);
});

test("Rider earnings reconciliation is audited and does not mutate balances", () => {
  const source = fs.readFileSync("rider-earnings-summary.js", "utf8");
  const index = fs.readFileSync("index.js", "utf8");
  assert.match(source, /function adminReconcileRiderEarnings\(\)/);
  assert.match(source, /const scheduledRiderEarningsReconciliation = functions\.pubsub\.schedule\("every 24 hours"\)/);
  assert.match(source, /collection\("riderEarningsReconciliations"\)\.doc\(\)/);
  assert.match(source, /reconciliationRequired: !result\.reconciled/);
  assert.match(source, /lastReconciliationId: recordRef\.id/);
  assert.match(source, /productionCount: result\.production\.length/);
  assert.doesNotMatch(source, /availableBalance:\s*FieldValue\.increment/);
  assert.doesNotMatch(source, /availableBalance:\s*result\.calculatedAvailable/);
  assert.match(index, /exports\.adminReconcileRiderEarnings = riderEarningsSummary\.adminReconcileRiderEarnings\(\);/);
  assert.match(index, /exports\.scheduledRiderEarningsReconciliation = riderEarningsSummary\.scheduledRiderEarningsReconciliation;/);
});
