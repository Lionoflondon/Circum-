/* eslint-disable max-len */
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const source = (name) => fs.readFileSync(path.join(__dirname, name), "utf8");

test("offer discovery and acceptance require canonical dispatchable presence", () => {
  const nearby = source("get-avaliable-requests.js");
  const accept = source("accept-ride-requests.js");
  assert.match(nearby, /requireDispatchablePresence\(riderId, riderData\)/);
  assert.match(accept, /requireDispatchablePresence\(riderId, rider\)/);
  assert.match(accept, /dispatchablePresenceDecision/);
  assert.match(accept, /activeDeliveryId/);
  assert.match(accept, /runTransaction/);
});

test("terminal delivery is deferred until authoritative settlement is available", () => {
  const tracking = source("delivery-tracking.js");
  assert.match(tracking, /status: "settlement_pending"/);
  assert.match(tracking, /settlementStatus: "pending_authority"/);
  assert.match(tracking, /reconcilePendingDeliverySettlements/);
  assert.match(tracking, /riderEarningTransactions/);
  assert.match(tracking, /completedDeliveries: FieldValue\.increment\(1\)/);
  assert.match(tracking, /riderTrustRankPatch/);
});

test("cancellation and no-show compensation post one idempotent Rider ledger entry", () => {
  const policy = source("delivery-policy.js");
  assert.match(policy, /function recordRiderCompensation/);
  assert.match(policy, /type: financial\.chargeType === "no_show_fee" \? "no_show_compensation" : "cancellation_compensation"/);
  assert.match(policy, /transaction\.create\(db\.collection\("riderEarningTransactions"\)/);
  assert.equal((policy.match(/recordRiderCompensation\(transaction, db, financial\)/g) || []).length, 3);
});

test("lifecycle callables use protected App Check wrappers", () => {
  const policy = source("delivery-policy.js");
  for (const callable of ["recordRiderArrival", "recordArrivalZoneCheck", "reportWaitingContext", "markRiderNoShow"]) {
    assert.match(policy, new RegExp(`exports\\.${callable} = riderCallable`));
  }
  for (const callable of ["requestSenderCancellation", "previewSenderCancellation", "recordCustomerArrivalResponse"]) {
    assert.match(policy, new RegExp(`exports\\.${callable} = senderPaymentCallable`));
  }
});

test("delivery lifecycle notifications use deterministic event keys", () => {
  const notifications = source("platform-notifications.js");
  const engine = source("communication-engine.js");
  assert.match(notifications, /dedupeKey: `\$\{change\.after\.id\}:\$\{status\}:sender:/);
  assert.match(engine, /normalizedDedupeKey/);
  assert.match(engine, /if \(!created\) return ref\.id/);
});
