/* eslint-disable max-len */
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const index = fs.readFileSync(path.join(__dirname, "index.js"), "utf8");
const cancellation = fs.readFileSync(path.join(__dirname, "delivery-policy.js"), "utf8");
const mobile = fs.readFileSync(path.join(__dirname, "../../lib/app/send_package/bloc/send_package_bloc.dart"), "utf8");
const web = fs.readFileSync(path.join(__dirname, "../../lib/web_sender_app.dart"), "utf8");

test("financial endpoints use CORS preflight and idempotent earnings", () => {
  assert.match(index, /function allowCors\(req, res\)/);
  assert.match(index, /riderEarnings\.creditRiderEarnings/);
  assert.doesNotMatch(index, /accountBalance:\s*riderBalance\s*\+/);
});

test("canonical cancellation is exported, auditable and refund-review aware", () => {
  assert.match(index, /exports\.cancelDelivery\s*=\s*deliveryPolicy\.requestSenderCancellation/);
  for (const field of ["previousLifecycleState", "cancellationReason", "refundReviewRequired", "stripePaymentIntentId", "deliveryTimeline"]) {
    assert.match(cancellation, new RegExp(field));
  }
});

test("Sender clients wait for the cancellation callable and never delete the delivery", () => {
  assert.match(mobile, /httpsCallable\('cancelDelivery'\)/);
  assert.doesNotMatch(mobile, /data\?\['status'\] == 'requested'[\s\S]{0,100}delete\(\)/);
  assert.match(web, /httpsCallable\('cancelDelivery'\)/);
  assert.doesNotMatch(web, /transaction\.update\(reference,[\s\S]{0,200}'cancelled_by_sender'/);
});

test("payment intents and Stripe refunds map back to deliveries", () => {
  assert.match(index, /stripePaymentIntentId:\s*intent\.id/);
  assert.match(index, /event\.type === "charge\.refunded"/);
});
