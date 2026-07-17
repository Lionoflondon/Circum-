/* eslint-disable require-jsdoc */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const indexSource = fs.readFileSync(path.join(__dirname, "index.js"), "utf8");
const accountBlocPath = path.join(
    __dirname,
    "..",
    "..",
    "lib",
    "app",
    "account",
    "bloc",
    "account_bloc.dart",
);
const paymentViewPath = path.join(
    __dirname,
    "..",
    "..",
    "lib",
    "app",
    "account",
    "view",
    "payment.dart",
);
const accountBlocSource = fs.readFileSync(accountBlocPath, "utf8");
const paymentViewSource = fs.readFileSync(paymentViewPath, "utf8");
const methodExportPattern = new RegExp(
    "exports\\.StripePayEndpointMethodId\\s*=\\s*" +
    "functions\\.https\\.onRequest\\(createPaymentIntentHandler\\)",
);
const createExportPattern = new RegExp(
    "exports\\.createPaymentIntent\\s*=\\s*" +
    "functions\\.https\\.onRequest\\(createPaymentIntentHandler\\)",
);

test("core delivery payment endpoints share the secured handler", () => {
  assert.match(indexSource, methodExportPattern);
  assert.match(indexSource, createExportPattern);
  assert.match(indexSource, /requireHttpSender\(req\)/);
  assert.match(indexSource, /getAuth\(\)\.verifyIdToken/);
});

test("core delivery payment ignores client amount for Stripe charge", () => {
  assert.doesNotMatch(indexSource, /const\s+orderAmount\s*=\s*amount/);
  assert.doesNotMatch(indexSource, /amount:\s*orderAmount/);
  assert.match(indexSource, /authoritativeAmountPence/);
  assert.match(indexSource, /stripe\.paymentIntents\.create\(params,\s*\{/);
  assert.match(indexSource, /submittedAmountPence/);
  assert.match(indexSource, /pricingDiscrepancyPence/);
});

test("core payment derives amount from stored delivery or quote", () => {
  assert.match(indexSource, /deliveryRequests/);
  assert.match(indexSource, /blockedDeliveryStatus/);
  assert.match(indexSource, /terminalPaymentStatus/);
  assert.match(indexSource, /senderBooking\._private\.quotePayload/);
  assert.match(indexSource, /missing-authoritative-pricing/);
  assert.match(indexSource, /validateLegacyPricingInput/);
  assert.match(indexSource, /distanceMiles == null \|\| distanceMiles <= 0/);
  assert.match(indexSource, /weightKg == null \|\| weightKg <= 0/);
});

test("core payment protects ownership and duplicate sessions", () => {
  assert.match(indexSource, /owner !== sender\.uid/);
  assert.match(indexSource, /legacyCorePaymentSessions/);
  assert.match(indexSource, /idempotent:\s*true/);
  assert.match(indexSource, /core_delivery_\$\{idempotencyKey\}/);
});

test("sender mobile payment sends auth and booking inputs", () => {
  assert.match(accountBlocSource, /Authorization/);
  assert.match(accountBlocSource, /Bearer \$token/);
  assert.match(accountBlocSource, /pricingInput/);
  assert.match(paymentViewSource, /distanceMiles/);
  assert.match(paymentViewSource, /weightKg/);
  assert.match(paymentViewSource, /paymentRequestId/);
});
