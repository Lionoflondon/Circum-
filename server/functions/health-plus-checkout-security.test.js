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
const websiteSource = fs.readFileSync(path.join(
    __dirname,
    "..",
    "..",
    "lib",
    "website",
    "shared",
    "circum_website_app.dart",
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

test("Health+ checkout supports client-selected Roth without trusting client totals", () => {
  assert.match(source, /useRoth/);
  assert.match(source, /calculateWalletCheckout\(\{[\s\S]*?orderTotalGbp,[\s\S]*?walletBalanceGbp: walletBalance,[\s\S]*?selectedCurrency: "gbp"/);
  assert.match(source, /const rothAmount = split\.walletContributionGbp;/);
  assert.match(source, /const cardAmount = split\.remainingGbp;/);
  assert.match(source, /amountPence: recurring \? amountPence : Math\.round\(cardAmount \* 100\)/);
  assert.match(source, /rothLedger\.applyWalletDebit\(\{[\s\S]*?type: "health_payment"/);
  assert.match(source, /transactionId: `wallet_health_plus_\$\{bookingId\}`/);
});

test("Health+ subscriptions apply Roth to the first invoice without changing renewal pricing", () => {
  assert.match(source, /stripe\.coupons\.create\(\{[\s\S]*?duration: "once"/);
  assert.match(source, /rothAppliesTo: recurring \? "first_subscription_invoice" : "checkout"/);
  assert.match(source, /amountPence: recurring \? amountPence : Math\.round\(cardAmount \* 100\)/);
  assert.match(source, /discounts = \[\{coupon: coupon\.id\}\]/);
});

test("Health+ checkout finalizes partial Roth only after Stripe confirms", () => {
  assert.match(source, /exports\.handleHealthPlusCheckoutSession\s*=\s*async/);
  assert.match(source, /verifiedStripePaidGbpSession\(sessionData/);
  assert.match(source, /expectedAmountGBP: payment\.cardAmount/);
  assert.match(source, /const rothAmount = money\(payment\.rothAmount\)/);
  assert.doesNotMatch(source, /metadata\.cardAmountGbp \|\| Number\(sessionData\.amount_total/);
  assert.doesNotMatch(source, /metadata\.rothAmountGbp \|\| payment\.rothAmount/);
  assert.match(source, /stripeCheckoutSessionId: sessionData\.id/);
  assert.match(source, /markHealthPlusPaid\(\{[\s\S]*?method: rothAmount > 0 \? "roth_card" : "card"/);
  assert.match(indexSource, /healthPlus,/);
});

test("Health+ booking and Sender actions are backend-authoritative callables", () => {
  assert.match(source, /exports\.createHealthPlusBooking\s*=\s*functions\.https\.onCall/);
  assert.match(source, /exports\.updateSenderHealthPlusBooking\s*=\s*functions\.https\.onCall/);
  assert.match(indexSource, /exports\.createHealthPlusBooking\s*=\s*healthPlus\.createHealthPlusBooking/);
  assert.match(indexSource, /exports\.updateSenderHealthPlusBooking\s*=\s*healthPlus\.updateSenderHealthPlusBooking/);
  assert.match(source, /db\.runTransaction/);
  assert.match(source, /healthPlusBookingIdempotency/);
  assert.match(source, /auditHistory/);
  assert.match(source, /health_admin_\$\{pickupRef\.id\}_booking_created/);
  assert.match(source, /recipientRole: "admin"/);
  assert.match(source, /route: "admin_health_plus"/);
});

test("Sender Health+ UI does not write authoritative Health+ records directly", () => {
  assert.match(senderHealthSource, /httpsCallable\('createHealthPlusBooking'\)/);
  assert.match(senderHealthSource, /httpsCallable\('updateSenderHealthPlusBooking'\)/);
  assert.match(senderHealthSource, /httpsCallable\('getSenderRothBalance'\)/);
  assert.match(senderHealthSource, /'useRoth': _useRoth/);
  assert.doesNotMatch(senderHealthSource, /collection\('healthPlusProfiles'\)/);
  assert.doesNotMatch(senderHealthSource, /collection\('prescriptionPickups'\)/);
  assert.doesNotMatch(senderHealthSource, /collection\('recurringPickupSchedules'\)/);
  assert.doesNotMatch(senderHealthSource, /collection\('healthPlusPayments'\)/);
  assert.doesNotMatch(senderHealthSource, /Admin operations/);
  assert.doesNotMatch(senderHealthSource, /updateHealthPlusPickupStatus/);
});

test("Website Health+ UI does not write authoritative Health+ records directly", () => {
  assert.match(websiteSource, /httpsCallable\('createHealthPlusBooking'\)/);
  assert.match(websiteSource, /httpsCallable\('updateSenderHealthPlusBooking'\)/);
  assert.match(websiteSource, /httpsCallable\('getSenderRothBalance'\)/);
  assert.match(websiteSource, /'useRoth': _healthUseRoth/);
  assert.match(websiteSource, /updateHealthPlusPickupStatus/);
  assert.doesNotMatch(websiteSource, /collection\('healthPlusProfiles'\)/);
  assert.doesNotMatch(websiteSource, /collection\('prescriptionPickups'\)[\s\S]{0,160}\.(?:set|update|add|delete)\(/);
  assert.doesNotMatch(websiteSource, /collection\('recurringPickupSchedules'\)/);
  assert.doesNotMatch(websiteSource, /collection\('healthPlusPayments'\)/);
  assert.doesNotMatch(websiteSource, /collection\('healthPlusNotifications'\)/);
  assert.doesNotMatch(websiteSource, /collection\('healthPlusUsageEvents'\)/);
});
