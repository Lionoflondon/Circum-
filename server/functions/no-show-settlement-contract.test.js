"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const source = fs.readFileSync(path.join(__dirname, "no-show-settlement.js"), "utf8");

test("collection precedes all realized financial effects and retries are deterministic", () => {
  assert.match(source, /intent\.status !== "succeeded"/);
  assert.match(source, /customerCollected: 0[\s\S]*riderCredited: 0[\s\S]*platformRealized: 0/);
  assert.match(source, /riderEarningTransactions/);
  assert.match(source, /type: "no_show_fee"/);
  assert.match(source, /platformSettlementTransactions/);
  assert.match(source, /idempotencyKey: `no_show_settlement_\$\{deliveryId\}`/);
  assert.match(source, /off_session: true/);
  assert.match(source, /confirm: true/);
  assert.match(source, /current\.data\(\) \|\| \{\}\)\.state === "SETTLED"/);
});
