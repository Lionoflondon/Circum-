"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {reconcileLedger, connectReadiness} = require("./rider-earnings-summary");

test("positive balance is explicitly unreconciled when categories do not explain it", () => {
  const value = reconcileLedger([], {availableBalance: 1238.40}, []);
  assert.equal(value.reconciled, false); assert.equal(value.unexplained, 1238.40);
});
test("paid historical payout is not active and processing payout is", () => {
  assert.equal(reconcileLedger([], {}, [{status: "paid", amount: 2}]).activePayout, null);
  assert.equal(reconcileLedger([], {}, [{status: "processing", amount: 2}]).activePayout.status, "processing");
});
test("readiness remains separate from withdrawal state", () => { assert.equal(connectReadiness({stripeConnectStatus: "pending"}), "pending_verification"); });
test("ledger categories reconcile and duplicate idempotency is counted once", () => {
  const rows = [{type:"delivery_earning",amount:10,idempotencyKey:"a"},{type:"delivery_earning",amount:10,idempotencyKey:"a"},{type:"tip",amount:2},{type:"payout_reserved",amount:3},{type:"payout_failed_release",amount:3}];
  const value = reconcileLedger(rows, {availableBalance:12}, []); assert.equal(value.calculatedAvailable,12); assert.equal(value.reconciled,true);
});
test("fixtures are quarantined without deleting ledger money", () => { const value=reconcileLedger([{type:"delivery_earning",amount:50,isTest:true}],{},[]); assert.equal(value.production.length,0); assert.equal(value.quarantined.length,1); });
