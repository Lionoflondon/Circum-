/* eslint-disable max-len */
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const index = fs.readFileSync(path.join(__dirname, "index.js"), "utf8");
const cancellation = fs.readFileSync(path.join(__dirname, "delivery-policy.js"), "utf8");
const senderBooking = fs.readFileSync(path.join(__dirname, "sender-booking.js"), "utf8");
const mobile = fs.readFileSync(path.join(__dirname, "../../lib/app/send_package/bloc/send_package_bloc.dart"), "utf8");
const web = fs.readFileSync(path.join(
    __dirname,
    "../../lib/website/shared/circum_website_app.dart",
), "utf8");

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
  for (const field of ["matchingStatus", "dispatchStatus", "broadcastBlocked", "removedFromActiveQueues"]) {
    assert.match(cancellation, new RegExp(field));
  }
});

test("Sender clients wait for the cancellation callable and never delete the delivery", () => {
  assert.match(mobile, /httpsCallable\('requestSenderCancellation'\)/);
  assert.doesNotMatch(mobile, /data\?\['status'\] == 'requested'[\s\S]{0,100}delete\(\)/);
  assert.match(web, /httpsCallable\('cancelDelivery'\)/);
  assert.doesNotMatch(web, /transaction\.update\(reference,[\s\S]{0,200}'cancelled_by_sender'/);
  assert.doesNotMatch(web, /collection\('deliveryRequests'\)[\s\S]{0,300}\.delete\(\)/);
});

test("payment intents and Stripe refunds map back to deliveries", () => {
  assert.match(senderBooking, /stripe\.paymentIntents\.retrieve/);
  assert.match(senderBooking, /updateSenderPaymentIntentStatus\(stripe, intent/);
  assert.match(senderBooking, /async function handleSenderPaymentIntent\(stripe, intent, eventId = ""\)/);
  assert.match(senderBooking, /createPaidDeliveryFromSession\(stripe, sender/);
  assert.match(index, /senderBooking\.handleSenderPaymentIntent\(/);
  assert.match(senderBooking, /stripePaymentIntentId:\s*payment\.stripePaymentIntentId/);
  assert.match(index, /event\.type === "charge\.refunded"/);
});

test("Sender PaymentIntent webhook recovery does not depend on client return", () => {
  assert.match(index, /event\.type === "payment_intent\.succeeded"/);
  assert.match(index, /event\.type === "payment_intent\.payment_failed"/);
  assert.match(index, /event\.type === "payment_intent\.canceled"/);
  assert.match(senderBooking, /paymentType !== "delivery" && paymentType !== "sender_delivery_payment"/);
  assert.match(senderBooking, /if \(intent\.status !== "succeeded"\)/);
  assert.match(senderBooking, /Sender PaymentIntent metadata does not match payment session owner/);
  assert.match(senderBooking, /Sender PaymentIntent currency does not match payment session/);
  assert.match(senderBooking, /Sender PaymentIntent amount does not match payment session/);
  assert.match(senderBooking, /payment\.deliveryPayload \|\| \{\}/);
  assert.match(senderBooking, /idempotencyKey: payment\.idempotencyKey \|\| metadata\.idempotencyKey/);
  assert.match(senderBooking, /webhookCompletedAt: FieldValue\.serverTimestamp\(\)/);
});
