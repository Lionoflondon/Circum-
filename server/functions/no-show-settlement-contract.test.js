"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const source = fs.readFileSync(path.join(__dirname, "no-show-settlement.js"), "utf8");

test("collection precedes all realized financial effects and retries are deterministic", () => {
  assert.match(source, /customerCollected: 0[\s\S]*riderCredited: 0[\s\S]*platformRealized: 0/);
  assert.match(source, /riderEarningTransactions/);
  assert.match(source, /type: "no_show_fee"/);
  assert.match(source, /platformSettlementTransactions/);
  assert.match(source, /idempotencyKey: `no_show_settlement_\$\{deliveryId\}`/);
  assert.doesNotMatch(source, /paymentIntents\.create/);
  assert.match(source, /additionalCustomerCharge: 0/);
  assert.match(source, /deductedFromPaidAmount: 7/);
  assert.match(source, /current\.data\(\) \|\| \{\}\)\.state === "SETTLED"/);
});

test("scheduler and Admin retry reuse the canonical bounded processor", () => {
  assert.match(source, /where\("state", "==", "SETTLEMENT_PENDING"\)/);
  assert.match(source, /where\("nextAttemptAt", "<=", new Date\(\)\)/);
  assert.match(source, /limit\(Math\.min\(Math\.max\(1, limit\), 50\)\)/);
  assert.match(source, /processNoShowSettlement\(\{db, stripe, deliveryId: doc\.id\}\)/);
  assert.match(source, /enforceAppCheck: true/);
  assert.match(source, /requireAdmin\(context/);
  assert.match(source, /no_show_settlement_retry_requested/);
});

test("settlement records deterministic operational and receipt truth", () => {
  assert.match(source, /doc\(`no_show_settled_\$\{deliveryId\}`\)/);
  assert.match(source, /eventType: "NoShowSettlementApplied"/);
  assert.match(source, /customerCollected: 7[\s\S]*riderCredited: 4[\s\S]*platformRealized: 3/);
});
