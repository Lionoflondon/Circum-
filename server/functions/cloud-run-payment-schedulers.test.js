"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");

test("payment scheduler service exposes only bounded maintenance routes", () => {
  const source = fs.readFileSync("cloud-run-payment-schedulers.js", "utf8");
  const payoutSource = fs.readFileSync("rider-connect.js", "utf8");
  assert.match(source, /reconcileBusinessInvoiceCheckoutsCore/);
  assert.match(source, /scheduledRiderStripeStatusSyncCore/);
  assert.match(source, /recoverRiderPayoutsCore/);
  assert.match(source, /reconcilePendingDeliverySettlementsCore/);
  assert.match(source, /processHealthPlusRemindersCore/);
  assert.match(payoutSource, /FieldPath\.documentId\(\)/);
  assert.doesNotMatch(source, /createRiderTransferOrPayout\(stripeClient/);
  assert.doesNotMatch(source, /createBusinessInvoiceCheckout/);
});

test("payment scheduler container binds to Cloud Run PORT", () => {
  const source = fs.readFileSync("cloud-run-payment-schedulers.js", "utf8");
  assert.match(source, /process\.env\.PORT \|\| 8080/);
  assert.match(source, /"0\.0\.0\.0"/);
});

test("Pub/Sub Eventarc envelopes select only an explicit scheduler handler", () => {
  const {eventHandlerName} = require("./cloud-run-payment-schedulers");
  const wrap = (payload) => ({message: {data: Buffer.from(JSON.stringify(payload)).toString("base64")}});
  assert.equal(eventHandlerName(wrap({handler: "health"})), "health");
  assert.equal(eventHandlerName({data: wrap({handler: "scheduledRiderStripeStatusSync"})}), "scheduledRiderStripeStatusSync");
  assert.equal(eventHandlerName(wrap({handler: "scheduledRiderPayoutRecovery"})), "scheduledRiderPayoutRecovery");
  assert.equal(eventHandlerName(wrap({handler: 42})), "");
  assert.equal(eventHandlerName({message: {data: "%%%"}}), "");
});
