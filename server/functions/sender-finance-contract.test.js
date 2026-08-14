/* eslint-disable max-len */
"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const senderFinanceSource = fs.readFileSync(path.join(__dirname, "sender-finance.js"), "utf8");
const businessViewSource = fs.readFileSync(path.join(__dirname, "../../lib/app/business/business_view.dart"), "utf8");
const businessRepositorySource = fs.readFileSync(path.join(__dirname, "../../lib/app/business/business_repository.dart"), "utf8");

test("Sender payment method removal is retry-safe and clears removed defaults", () => {
  assert.match(senderFinanceSource, /function isStripeMissingResource/);
  assert.match(senderFinanceSource, /alreadyDetached: true/);
  assert.match(senderFinanceSource, /if \(!method\.customer\)/);
  assert.match(senderFinanceSource, /invoice_settings\.default_payment_method === paymentMethodId/);
  assert.match(senderFinanceSource, /invoice_settings: \{default_payment_method: null\}/);
  assert.match(senderFinanceSource, /action: "payment_method_removed"/);
});

test("Sender payment methods remain owned by Sender Stripe customer", () => {
  assert.match(senderFinanceSource, /const customerId = await ensureStripeCustomer\(\{stripe, sender\}\)/);
  assert.match(senderFinanceSource, /if \(method\.customer !== customerId\)/);
  assert.match(senderFinanceSource, /Payment method does not belong to this Sender/);
  assert.match(senderFinanceSource, /stripe\.paymentMethods\.detach\(paymentMethodId\)/);
  assert.match(senderFinanceSource, /stripe\.customers\.update\(customerId/);
});

test("Business may list Sender Wallet cards but pays through Business authority", () => {
  assert.match(businessViewSource, /FirebaseSenderPaymentProfileRepository\(\)/);
  assert.match(businessViewSource, /_paymentRepository\.paymentMethods\(\)/);
  assert.match(businessViewSource, /_BusinessInvoicePaymentSheet/);
  assert.match(businessRepositorySource, /httpsCallable\('createBusinessInvoiceCheckout'\)/);
  assert.doesNotMatch(businessRepositorySource, /httpsCallable\('createSenderPaymentSession'\)/);
  assert.doesNotMatch(businessRepositorySource, /httpsCallable\('createSenderPaidDelivery'\)/);
});
