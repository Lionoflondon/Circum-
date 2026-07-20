/* eslint-disable max-len */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const source = fs.readFileSync(path.join(__dirname, "health-plus.js"), "utf8");
const indexSource = fs.readFileSync(path.join(__dirname, "index.js"), "utf8");
const senderHealthSource = fs.readFileSync(path.join(
    __dirname,
    "..",
    "..",
    "lib",
    "app",
    "health_plus",
    "view",
    "health_plus.dart",
), "utf8");

test("Health+ checkout requires authenticated Sender ownership", () => {
  assert.match(source, /verifySenderRequest\(req\)/);
  assert.match(source, /getAuth\(\)\.verifyIdToken/);
  assert.match(source, /ownsBooking\(sender, booking\)/);
  assert.match(source, /ownsBooking\(sender, profile\)/);
});

test("Health+ checkout uses booking data, not submitted amount fields", () => {
  assert.match(source, /healthPlusPricingInputFromBooking\(booking, profile\)/);
  assert.match(source, /calculateAuthoritativeHealthPlusPricing/);
  assert.doesNotMatch(source, /calculateHealthPlusAmountPence\(\{[\s\S]*breakdown/);
  assert.doesNotMatch(source, /amountPence = .*priceBreakdown/);
});

test("Health+ checkout fails safely without authoritative pricing data", () => {
  assert.match(source, /checkout_pricing_failed/);
  assert.match(source, /failed-precondition/);
  assert.match(source, /requires route distance and medication weight/);
});

test("Health+ checkout is idempotent and blocks paid bookings", () => {
  assert.match(source, /existingPayment\.checkoutSessionId/);
  assert.match(source, /idempotent: true/);
  assert.match(source, /has already been paid/);
});

test("Health+ receipt stores server-calculated pricing and discrepancies", () => {
  assert.match(source, /authoritativePricing: authoritative/);
  assert.match(source, /submittedQuoteAmountPence/);
  assert.match(source, /pricingDiscrepancyPence/);
  assert.match(source, /checkout_price_discrepancy/);
});

test("Health+ booking and Sender actions are backend-authoritative callables", () => {
  assert.match(source, /exports\.createHealthPlusBooking\s*=\s*functions\.https\.onCall/);
  assert.match(source, /exports\.updateSenderHealthPlusBooking\s*=\s*functions\.https\.onCall/);
  assert.match(indexSource, /exports\.createHealthPlusBooking\s*=\s*healthPlus\.createHealthPlusBooking/);
  assert.match(indexSource, /exports\.updateSenderHealthPlusBooking\s*=\s*healthPlus\.updateSenderHealthPlusBooking/);
  assert.match(source, /db\.runTransaction/);
  assert.match(source, /healthPlusBookingIdempotency/);
  assert.match(source, /auditHistory/);
});

test("Sender Health+ UI does not write authoritative Health+ records directly", () => {
  assert.match(senderHealthSource, /httpsCallable\('createHealthPlusBooking'\)/);
  assert.match(senderHealthSource, /httpsCallable\('updateSenderHealthPlusBooking'\)/);
  assert.doesNotMatch(senderHealthSource, /collection\('healthPlusProfiles'\)/);
  assert.doesNotMatch(senderHealthSource, /collection\('prescriptionPickups'\)/);
  assert.doesNotMatch(senderHealthSource, /collection\('recurringPickupSchedules'\)/);
  assert.doesNotMatch(senderHealthSource, /collection\('healthPlusPayments'\)/);
  assert.doesNotMatch(senderHealthSource, /Admin operations/);
  assert.doesNotMatch(senderHealthSource, /updateHealthPlusPickupStatus/);
});
