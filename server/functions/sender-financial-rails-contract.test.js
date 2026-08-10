"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const booking = fs.readFileSync(path.join(__dirname, "sender-booking.js"), "utf8");
const finance = fs.readFileSync(path.join(__dirname, "sender-finance.js"), "utf8");

test("delivery payload is initialized before payment validation", () => {
  const start = booking.indexOf("exports.createSenderPaymentSession");
  const source = booking.slice(start, booking.indexOf("async function updateSenderPaymentIntentStatus", start));
  assert.ok(source.indexOf("const deliveryPayload = cleanMap(data.deliveryPayload)") <
    source.indexOf("Object.keys(deliveryPayload)"));
});

test("Sender Stripe customer records are ownership verified", () => {
  for (const source of [booking, finance]) {
    assert.match(source, /metadata[\s\S]*userId/);
    assert.match(source, /Stripe customer (does not belong|ownership could not be verified)/);
    assert.match(source, /sender_customer_\$\{sender\.uid\}/);
  }
});

test("Roth drift never resolves by selecting the larger balance", () => {
  assert.doesNotMatch(booking, /Math\.max\(\.\.\.availableBalances\)/);
  assert.doesNotMatch(booking, /Math\.max\(\.\.\.candidates\)/);
  assert.match(booking, /canonicalSenderWalletBalance/);
});
