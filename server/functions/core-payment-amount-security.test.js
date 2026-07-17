/* eslint-disable max-len, require-jsdoc */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const indexSource = fs.readFileSync(path.join(__dirname, "index.js"), "utf8");
const senderBookingSource = fs.readFileSync(path.join(__dirname, "sender-booking.js"), "utf8");
const accountBlocSource = fs.readFileSync(path.join(
    __dirname,
    "..",
    "..",
    "lib",
    "app",
    "account",
    "bloc",
    "account_bloc.dart",
), "utf8");
const sendBlocSource = fs.readFileSync(path.join(
    __dirname,
    "..",
    "..",
    "lib",
    "app",
    "send_package",
    "bloc",
    "send_package_bloc.dart",
), "utf8");
const reviewSource = fs.readFileSync(path.join(
    __dirname,
    "..",
    "..",
    "lib",
    "app",
    "send_package",
    "view",
    "delivery_review_expanded.dart",
), "utf8");

test("legacy standard delivery payment HTTP endpoints are retired", () => {
  assert.doesNotMatch(indexSource, /exports\.StripePayEndpointMethodId/);
  assert.doesNotMatch(indexSource, /exports\.createPaymentIntent/);
  assert.doesNotMatch(indexSource, /exports\.StripePayEndpointIntentId/);
  assert.doesNotMatch(indexSource, /exports\.confirmPaymentIntent/);
  assert.doesNotMatch(indexSource, /createPaymentIntentHandler/);
  assert.doesNotMatch(indexSource, /legacyCorePaymentSessions/);
  assert.doesNotMatch(accountBlocSource, /createPaymentIntent/);
  assert.doesNotMatch(accountBlocSource, /confirmPaymentIntent/);
});

test("Sender mobile uses canonical quote, payment session, and paid delivery callables", () => {
  assert.match(accountBlocSource, /httpsCallable\('createSenderBookingQuote'\)/);
  assert.match(accountBlocSource, /httpsCallable\('createSenderPaymentSession'\)/);
  assert.match(sendBlocSource, /httpsCallable\('createSenderPaidDelivery'\)/);
  assert.doesNotMatch(sendBlocSource, /httpsCallable\('sendPackage'\)/);
  assert.doesNotMatch(sendBlocSource, /collection\("deliveryRequests"\)\.doc\(user\?\.uid\)\.set/);
  assert.match(reviewSource, /quoteId: accountState\.quoteId/);
  assert.match(reviewSource, /paymentSessionId: accountState\.paymentSessionId/);
});

test("canonical payment authority calculates and records authoritative pricing", () => {
  assert.match(senderBookingSource, /exports\.createSenderBookingQuote/);
  assert.match(senderBookingSource, /quotePayload\(data \|\| \{\}, sender\.uid\)/);
  assert.match(senderBookingSource, /clientDisplayQuote/);
  assert.match(senderBookingSource, /pricingDiscrepancyPence/);
  assert.match(senderBookingSource, /exports\.createSenderPaymentSession/);
  assert.match(senderBookingSource, /const quoteSnap = await db\.collection\("senderBookingQuotes"\)/);
  assert.match(senderBookingSource, /quoteSnap\.data\(\)\.userId !== sender\.uid/);
  assert.match(senderBookingSource, /calculateWalletCheckout/);
  assert.match(senderBookingSource, /collection\("senderPaymentSessions"\)\.doc\(quoteId\)/);
  assert.match(senderBookingSource, /existingSessionSnap\.exists/);
  assert.match(senderBookingSource, /stripe\.paymentIntents\.create/);
  assert.match(senderBookingSource, /const idempotencyKey = `sender_booking_\$\{quoteId\}`/);
});

test("canonical paid delivery finalization requires succeeded payment and is idempotent", () => {
  assert.match(senderBookingSource, /exports\.createSenderPaidDelivery/);
  assert.match(senderBookingSource, /paymentSessionId/);
  assert.match(senderBookingSource, /Stripe payment must be confirmed before delivery creation/);
  assert.match(senderBookingSource, /senderDeliveryIdempotency/);
  assert.match(senderBookingSource, /paymentStatus: "paid"/);
  assert.match(senderBookingSource, /pricingBreakdown: quote/);
});
