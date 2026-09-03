/* eslint-disable max-len */
"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {_private} = require("./sender-booking");

const bookingSource = fs.readFileSync(path.join(__dirname, "sender-booking.js"), "utf8");
const financeSource = fs.readFileSync(path.join(__dirname, "sender-finance.js"), "utf8");

function resumableIntent(overrides = {}) {
  return {
    id: "pi_sender",
    customer: "cus_sender",
    client_secret: "pi_sender_secret",
    metadata: {
      userId: "sender-1",
      quoteId: "quote-1",
      paymentSessionId: "quote-1",
    },
    ...overrides,
  };
}

function resume(intent) {
  return _private.resumeExistingSenderPaymentIntent({
    stripe: {paymentIntents: {retrieve: async () => intent}},
    existingSession: {
      stripePaymentIntentId: "pi_sender",
      stripeCustomerId: "cus_sender",
    },
    sender: {uid: "sender-1"},
    quoteId: "quote-1",
    paymentSessionId: "quote-1",
  });
}

test("legacy Sender payment sessions resume from Stripe, not stored client secrets", async () => {
  const intent = resumableIntent();
  assert.equal(await resume(intent), intent);
  assert.match(bookingSource, /stripe\.paymentIntents\.retrieve\(paymentIntentId\)/);
  assert.match(bookingSource, /clientSecret: FieldValue\.delete\(\)/);
  assert.doesNotMatch(bookingSource, /clientSecret: existingSession\.clientSecret/);
});

test("foreign PaymentIntents cannot be resumed", async () => {
  await assert.rejects(
      resume(resumableIntent({customer: "cus_foreign"})),
      (error) => error.code === "permission-denied",
  );
  await assert.rejects(
      resume(resumableIntent({metadata: {
        userId: "foreign-sender",
        quoteId: "quote-1",
        paymentSessionId: "quote-1",
      }})),
      (error) => error.code === "permission-denied",
  );
});

test("ordinary card checkout is one-time and client secrets are response-only", () => {
  assert.doesNotMatch(bookingSource, /setup_future_usage/);
  const tippingSource = fs.readFileSync(require.resolve("./ratings-tipping"), "utf8");
  assert.doesNotMatch(tippingSource, /setup_future_usage/);
  assert.equal(
      bookingSource.match(/clientSecret: intent\.client_secret/g)?.length,
      1,
  );
  const paymentIntentWrite = bookingSource.match(
      /await sessionRef\.set\(\{\n\s{4}\.\.\.sessionBase,\n\s{4}status: intent\.status,[\s\S]*?\n\s{2}\}\);/,
  );
  assert.ok(paymentIntentWrite, "PaymentIntent session write not found");
  assert.doesNotMatch(paymentIntentWrite[0], /clientSecret|client_secret/);
  assert.doesNotMatch(bookingSource, /console\.(?:log|info|warn|error)\([^\n]*(?:clientSecret|client_secret)/);
});

test("explicit Add Card remains SetupIntent-backed", () => {
  assert.match(financeSource, /stripe\.setupIntents\.create\(\{/);
  assert.match(financeSource, /usage: "off_session"/);
  assert.match(financeSource, /payment_method_types: \["card"\]/);
  assert.match(financeSource, /setupIntentClientSecret: setupIntent\.client_secret/);
});

test("saved-card operations retain authenticated ownership checks", () => {
  assert.match(financeSource, /if \(method\.customer !== customerId\)/);
  assert.match(bookingSource, /if \(method\.customer !== customerId\)/);
  assert.match(financeSource, /stripe\.paymentMethods\.detach\(paymentMethodId\)/);
  assert.match(financeSource, /default_payment_method: paymentMethodId/);
});

test("removing a default card clears stale default authority", () => {
  assert.match(
      financeSource,
      /default_payment_method === paymentMethodId/,
  );
  assert.match(
      financeSource,
      /invoice_settings: \{default_payment_method: null\}/,
  );
  assert.match(
      financeSource,
      /defaultPaymentMethodId: FieldValue\.delete\(\)/,
  );
});
