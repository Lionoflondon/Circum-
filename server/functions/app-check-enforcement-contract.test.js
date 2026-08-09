"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

function source(name) {
  return fs.readFileSync(path.join(__dirname, name), "utf8");
}

test("financial and lifecycle mutation callables require App Check", () => {
  const expectations = [
    ["sender-booking.js", /createSenderBookingQuote\s*=\s*functions\.runWith\([\s\S]*?enforceAppCheck: true/],
    ["sender-booking.js", /createSenderPaymentSession\s*=\s*\(stripe\) => functions\.runWith\(\{enforceAppCheck: true\}\)/],
    ["sender-booking.js", /createSenderPaidDelivery\s*=\s*\(stripe\) => functions\.runWith\(\{[\s\S]*?enforceAppCheck: true,[\s\S]*?GOOGLE_PLACES_API_KEY[\s\S]*?\}\)/],
    ["sender-booking.js", /finalizeSenderWebCheckout\s*=\s*\(stripe\) => functions\.runWith\(\{enforceAppCheck: true\}\)/],
    ["business-payments.js", /createBusinessRothCheckout\s*=\s*\(stripe\) => functions\.runWith\(\{enforceAppCheck: true\}\)/],
    ["business-payments.js", /createBusinessInvoiceCheckout\s*=\s*\(stripe\) => functions\.runWith\(\{enforceAppCheck: true\}\)/],
    ["health-plus.js", /createHealthPlusBooking\s*=\s*functions\.runWith\([\s\S]*?enforceAppCheck: true/],
    ["gifts-payment.js", /createGiftPayment\s*=\s*\(stripe\) => functions\.runWith\(\{[\s\S]*?enforceAppCheck: true,[\s\S]*?GOOGLE_PLACES_API_KEY[\s\S]*?\}\)/],
    ["gifts-payment.js", /finalizeGiftPayment\s*=\s*\(stripe\) => functions\.runWith\(\{enforceAppCheck: true\}\)/],
    ["accept-ride-requests.js", /const acceptRideRequests = functions\.runWith\(\{enforceAppCheck: true\}\)/],
    ["scheduled-road-charge-refunds.js", /const settleScheduledRoadChargeCashRefund = functions\.runWith\(\{enforceAppCheck: true\}\)/],
  ];
  for (const [file, pattern] of expectations) {
    assert.match(source(file), pattern, `${file} is missing enforced App Check`);
  }
});

test("public address lookup remains intentionally callable without financial mutation enforcement", () => {
  const freeAddress = source("free-address-search.js");
  assert.match(freeAddress, /const googlePlacesApiKeySecret = defineSecret\("GOOGLE_PLACES_API_KEY"\)/);
  assert.match(freeAddress, /searchFreeUkAddresses = functions\.runWith\(\{secrets: \[googlePlacesApiKeySecret\]\}\)\.https\.onCall/);
  assert.match(freeAddress, /resolveUkAddressPlace = functions\.runWith\(\{secrets: \[googlePlacesApiKeySecret\]\}\)\.https\.onCall/);
});
