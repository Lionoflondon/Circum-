const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

function source(name) {
  return fs.readFileSync(path.join(__dirname, name), "utf8");
}

function between(input, start, end) {
  const startIndex = input.indexOf(start);
  assert.notEqual(startIndex, -1, `Missing ${start}`);
  const endIndex = input.indexOf(end, startIndex + start.length);
  assert.notEqual(endIndex, -1, `Missing ${end}`);
  return input.slice(startIndex, endIndex);
}

test("Gift checkout claims one deterministic payment before Stripe creation", () => {
  const gift = between(
      source("gifts-payment.js"),
      "exports.createGiftPayment",
      "async function finalizeGiftPaymentSession",
  );
  assert.match(gift, /checkoutLogicalKey\("gift", \{giftDraftId\}\)/);
  assert.match(gift, /db\.runTransaction/);
  assert.match(gift, /checkoutClaim\(current/);
  assert.match(gift, /createStripeCheckoutOnce\(\{/);
  assert.doesNotMatch(gift, /stripe\.checkout\.sessions\.create\(/);
  assert.match(gift, /checkoutUrl: session\.url/);
  assert.match(gift, /returnOwner: requestedReturnOwner/);
});

test("Health+ checkout claims one booking payment and verifies the final Stripe Session", () => {
  const healthSource = source("health-plus.js");
  const checkout = between(
      healthSource,
      "exports.createHealthPlusCheckoutSession",
      "exports.handleHealthPlusCheckoutSession",
  );
  assert.match(checkout, /checkoutLogicalKey\("health_plus", \{bookingId\}\)/);
  assert.match(checkout, /db\.runTransaction/);
  assert.match(checkout, /checkoutClaim\(current/);
  assert.match(checkout, /createStripeCheckoutOnce\(\{/);
  assert.match(checkout, /paymentChannel: "roth"/);
  assert.match(checkout, /paymentChannel: "stripe_checkout"/);
  assert.match(checkout, /already has a card checkout in progress/);
  assert.match(checkout, /already has a Roth payment in progress/);
  assert.doesNotMatch(checkout, /stripe\.checkout\.sessions\.create\(/);
  assert.match(
      healthSource,
      /payment\.checkoutSessionId !== sessionData\.id[\s\S]*Health\+ checkout session ownership mismatch/,
  );
});

test("Business invoice checkout uses one deterministic record for the invoice balance state", () => {
  const businessSource = source("business-payments.js");
  const checkout = between(
      businessSource,
      "exports.createBusinessInvoiceCheckout",
      "exports.handleBusinessCheckoutSession",
  );
  assert.match(checkout, /checkoutLogicalKey\("business_invoice"/);
  assert.match(checkout, /invoiceBalancePence/);
  assert.match(checkout, /\.doc\(`invoice_\$\{checkoutLogicalIdentity\}`\)/);
  assert.match(checkout, /db\.runTransaction/);
  assert.match(checkout, /checkoutClaim\(current/);
  assert.match(checkout, /createStripeCheckoutOnce\(\{/);
  assert.match(checkout, /paymentChannel: "roth"/);
  assert.match(checkout, /paymentChannel: "stripe_checkout"/);
  assert.match(checkout, /already has a card checkout in progress/);
  assert.match(checkout, /already has a Roth payment in progress/);
  assert.doesNotMatch(checkout, /stripe\.checkout\.sessions\.create\(/);
  assert.match(
      businessSource,
      /payment\.checkoutSessionId \|\| payment\.stripeSessionId[\s\S]*Business invoice checkout session ownership mismatch/,
  );
});

test("Sender delivery checkout resumes its claimed quote instead of incrementing attempts", () => {
  const sender = between(
      source("sender-booking.js"),
      "exports.createSenderPaymentSession",
      "exports.createSenderPaidDelivery",
  );
  assert.match(sender, /checkoutLogicalKey\("sender_delivery"/);
  assert.match(sender, /db\.runTransaction/);
  assert.match(sender, /checkoutClaim\(current/);
  assert.match(sender, /webCheckoutClaim\.kind === "reuse"/);
  assert.match(sender, /createStripeCheckoutOnce\(\{/);
  assert.match(sender, /paymentCreationClaimKey/);
  assert.match(sender, /paymentChannel: "payment_intent"/);
  assert.match(sender, /paymentChannel: "roth"/);
  assert.match(sender, /already has an in-app payment in progress/);
  assert.match(sender, /already has a web checkout in progress/);
  assert.match(sender, /already has a card payment in progress/);
  assert.match(sender, /const idempotencyKey = stableId\([\s\S]*draftId \|\| "roth"/);
  assert.doesNotMatch(sender, /checkoutAttempt/);
  assert.doesNotMatch(sender, /web_checkout_retry_forces_fresh_session/);
});
