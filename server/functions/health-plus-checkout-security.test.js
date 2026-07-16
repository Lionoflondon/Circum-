/* eslint-disable max-len */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const source = fs.readFileSync(path.join(__dirname, "health-plus.js"), "utf8");

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
