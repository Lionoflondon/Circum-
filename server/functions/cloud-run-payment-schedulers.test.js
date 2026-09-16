"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");

test("payment scheduler service exposes only the two required maintenance routes", () => {
  const source = fs.readFileSync("cloud-run-payment-schedulers.js", "utf8");
  assert.match(source, /reconcileBusinessInvoiceCheckoutsCore/);
  assert.match(source, /scheduledRiderStripeStatusSyncCore/);
  assert.doesNotMatch(source, /createRiderTransferOrPayout/);
  assert.doesNotMatch(source, /createBusinessInvoiceCheckout/);
});

test("payment scheduler container binds to Cloud Run PORT", () => {
  const source = fs.readFileSync("cloud-run-payment-schedulers.js", "utf8");
  assert.match(source, /process\.env\.PORT \|\| 8080/);
  assert.match(source, /"0\.0\.0\.0"/);
});
