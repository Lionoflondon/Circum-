"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

test("paid delivery finalization derives canonical addresses from paid quote", () => {
  const source = fs.readFileSync(
      path.join(__dirname, "sender-booking.js"),
      "utf8",
  );
  const start = source.indexOf("async function createPaidDeliveryFromSession");
  const end = source.indexOf("exports.createSenderPaidDelivery", start);
  assert.ok(start >= 0 && end > start);
  const finalization = source.slice(start, end);

  assert.match(finalization, /canonicalAddressPair\(\{[\s\S]*quote\.pickupAddressCanonical[\s\S]*quote\.dropoffAddressCanonical/);
  assert.doesNotMatch(finalization, /resolveCanonicalAddressPair\(data \|\| \{\}\)/);
  assert.match(finalization, /paid quote is missing verified booking addresses/i);
});
