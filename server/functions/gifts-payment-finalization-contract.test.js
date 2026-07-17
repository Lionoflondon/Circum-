/* eslint-disable max-len */
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const source = fs.readFileSync(path.join(__dirname, "gifts-payment.js"), "utf8");
const router = fs.readFileSync(path.join(__dirname, "checkout-session-router.js"), "utf8");
const index = fs.readFileSync(path.join(__dirname, "index.js"), "utf8");

test("Gift finalization verifies authoritative Stripe session state", () => {
  assert.match(source, /session\.payment_status !== "paid"/);
  assert.match(source, /session\.currency !== "gbp"/);
  assert.match(source, /Number\(session\.amount_total \|\| 0\) !== expectedAmount/);
  assert.match(source, /session\.id !== gift\.stripeCheckoutSessionId/);
  assert.match(source, /gift\.senderId !== actorUid/);
});

test("Gift finalization is idempotent for duplicate webhook or client recovery", () => {
  assert.match(source, /existingGiftSnap\.exists/);
  assert.match(source, /existing\.paymentStatus === "paid"/);
  assert.match(source, /giftPaymentEvents/);
  assert.match(source, /eventId \? "stripe_webhook" : "client_recovery"/);
});

test("Stripe Checkout webhook routes gift_experience through the Gift finalizer", () => {
  assert.match(router, /type === "gift_experience"/);
  assert.match(router, /finalizeGiftPaymentFromCheckoutSession/);
  assert.match(index, /giftsPayment,/);
});
