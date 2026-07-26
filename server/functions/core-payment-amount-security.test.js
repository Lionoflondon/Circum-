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
const accountStateSource = fs.readFileSync(path.join(
    __dirname,
    "..",
    "..",
    "lib",
    "app",
    "account",
    "bloc",
    "account_state.dart",
), "utf8");
const webSenderSource = fs.readFileSync(path.join(
    __dirname,
    "..",
    "..",
    "lib",
    "website",
    "shared",
    "circum_website_app.dart",
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
  assert.match(sendBlocSource, /_callableMap\('createSenderPaidDelivery'/);
  assert.doesNotMatch(sendBlocSource, /collection\("deliveryRequests"\)\.doc\(user\?\.uid\)\.set/);
  assert.match(accountStateSource, /final String\? quoteId/);
  assert.match(accountStateSource, /final String\? paymentSessionId/);
  assert.match(accountBlocSource, /quoteId:\s*paymentIntentResult\['quoteId'\]/);
  assert.match(accountBlocSource, /paymentSessionId:\s*paymentIntentResult\['paymentSessionId'\]/);
});

test("canonical payment authority calculates and records authoritative pricing", () => {
  assert.match(senderBookingSource, /exports\.createSenderBookingQuote/);
  assert.match(senderBookingSource, /verifiedPhotoAnalysis\(\{/);
  assert.match(senderBookingSource, /quotePayload\(data \|\| \{\}, sender\.uid, serverPhotoAnalysis\)/);
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

test("canonical backend delivery records include Rider display aliases", () => {
  assert.match(senderBookingSource, /const RIDER_DELIVERY_FARE_SHARE = 0\.65/);
  assert.match(senderBookingSource, /function riderDisplayAliases\(/);
  assert.match(senderBookingSource, /function riderPayoutFromQuote\(/);
  assert.match(senderBookingSource, /totalRiderEarnings/);
  assert.match(senderBookingSource, /const riderAliases = riderDisplayAliases\(\{quote, data, vanguardFields\}\)/);
  assert.match(senderBookingSource, /\.\.\.riderAliases/);
  assert.match(senderBookingSource, /riderEarning: riderPayout/);
  assert.match(senderBookingSource, /distanceText: distanceMiles > 0/);
  assert.match(senderBookingSource, /durationText: durationMinutes > 0/);
  assert.match(senderBookingSource, /requiresVanguard: vanguardFields\.vanguardProtocolEnabled === true/);
  assert.match(senderBookingSource, /pickupWindow: pickupWindow \|\| null/);
});

test("Sender Web checkout uses canonical payment callables and never writes paid deliveries directly", () => {
  const confirmPaymentMatch = webSenderSource.match(/Future<void> _confirmPayment\(\) async \{[\s\S]*?\n {2}Future<bool\?> _confirmAuthoritativeWebQuote/);
  assert.ok(confirmPaymentMatch, "web _confirmPayment implementation not found");
  const confirmPaymentSource = confirmPaymentMatch[0];
  assert.match(confirmPaymentSource, /httpsCallable\('createSenderBookingQuote'\)/);
  assert.match(confirmPaymentSource, /httpsCallable\('createSenderPaymentSession'\)/);
  assert.match(confirmPaymentSource, /Stripe\.instance\.presentPaymentSheet/);
  assert.match(confirmPaymentSource, /httpsCallable\('createSenderPaidDelivery'\)/);
  assert.doesNotMatch(confirmPaymentSource, /collection\('webSenderRequests'\)/);
  assert.doesNotMatch(confirmPaymentSource, /collection\('deliveryRequests'\)\.doc\(id\)/);
  assert.doesNotMatch(confirmPaymentSource, /collection\('chats'\)/);
  assert.doesNotMatch(confirmPaymentSource, /batch\.commit\(\)/);
});

test("legacy endTrip handles missing requests before reading delivery data", () => {
  assert.match(
      indexSource,
      /collection\("deliveryRequests"\)\.where\("requestId", "==", requestId\)\.limit\(1\)\.get\(\)/,
  );
  assert.match(indexSource, /if \(ride\.empty\) \{\s*return res\.status\(404\)\.send\(\{msg: "Trip already completed"\}\);\s*\}/);
  assert.doesNotMatch(
      indexSource,
      /const rideData = ride\.docs\[0\];\s*const rideDataRes = rideData\.data\(\);\s*if \(!rideData\.exists\)/,
  );
});
