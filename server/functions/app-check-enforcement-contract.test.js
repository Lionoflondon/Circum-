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
    ["sender-finance.js", /listSenderPaymentMethods\s*=\s*\(stripe\) => functions\.runWith\(\{enforceAppCheck: true\}\)/],
    ["sender-finance.js", /createSenderSetupIntent\s*=\s*\(stripe\) => functions\.runWith\(\{enforceAppCheck: true\}\)/],
    ["sender-finance.js", /detachSenderPaymentMethod\s*=\s*\(stripe\) => functions\.runWith\(\{enforceAppCheck: true\}\)/],
    ["sender-finance.js", /setDefaultSenderPaymentMethod\s*=\s*\(stripe\) => functions\.runWith\(\{enforceAppCheck: true\}\)/],
    ["sender-finance.js", /saveSenderCheckoutPreference\s*=\s*functions\.runWith\(\{enforceAppCheck: true\}\)/],
    ["roth-ledger.js", /createWalletTopUp\s*=\s*\(stripe\) => functions\.runWith\(\{enforceAppCheck: true\}\)/],
    ["roth-ledger.js", /applyCheckoutRoth\s*=\s*functions\.runWith\(\{enforceAppCheck: true\}\)/],
    ["roth-ledger.js", /requestSenderWalletDebit\s*=\s*functions\.runWith\(\{enforceAppCheck: true\}\)/],
    ["roth-ledger.js", /requestSenderWalletRefund\s*=\s*functions\.runWith\(\{enforceAppCheck: true\}\)/],
    ["business-payments.js", /createBusinessRothCheckout\s*=\s*\(stripe\) => functions\.runWith\(\{enforceAppCheck: true\}\)/],
    ["business-payments.js", /createBusinessInvoiceCheckout\s*=\s*\(stripe\) => functions\.runWith\(\{enforceAppCheck: true\}\)/],
    ["health-plus.js", /createHealthPlusBooking\s*=\s*functions\.runWith\([\s\S]*?enforceAppCheck: true/],
    ["gifts-payment.js", /createGiftPayment\s*=\s*\(stripe\) => functions\.runWith\(\{[\s\S]*?enforceAppCheck: true,[\s\S]*?GOOGLE_PLACES_API_KEY[\s\S]*?\}\)/],
    ["gifts-payment.js", /finalizeGiftPayment\s*=\s*\(stripe\) => functions\.runWith\(\{enforceAppCheck: true\}\)/],
    ["accept-ride-requests.js", /const acceptRideRequests = functions\.runWith\(\{enforceAppCheck: true\}\)/],
    ["send-package.js", /const sendPackage = functions\.runWith\(\{enforceAppCheck: true\}\)/],
    ["get-avaliable-requests.js", /const getNearbyRequests = functions\.runWith\(\{enforceAppCheck: true\}\)/],
    ["send-rider-update.js", /const sendRiderUpdate = functions\.runWith\(\{enforceAppCheck: true\}\)/],
    ["scheduled-road-charge-refunds.js", /const settleScheduledRoadChargeCashRefund = functions\.runWith\(\{enforceAppCheck: true\}\)/],
    ["iris.js", /const analyseIris = functions\.runWith\(\{enforceAppCheck: true\}\)\.https\.onCall/],
    ["iris.js", /const getIrisHealthMetrics = functions\.runWith\(\{enforceAppCheck: true\}\)\.https\.onCall/],
    ["iris.js", /const adjudicateIris = functions\.runWith\(\{enforceAppCheck: true\}\)\.https\.onCall/],
    ["iris-photo-analysis.js", /const analyseParcelPhotoForIris = functions\.runWith\(\{enforceAppCheck: true\}\)\.https\.onCall/],
    ["iris-photo-analysis.js", /const adminSetIrisVisualModelState = functions\.runWith\(\{enforceAppCheck: true\}\)\.https\.onCall/],
    ["delivery-adjustments.js", /exports\.reportLoadDiscrepancy = functions\.runWith\(\{enforceAppCheck: true\}\)\.https\.onCall/],
    ["delivery-evidence.js", /exports\.recordDeliveryEvidence = functions\.runWith\(\{enforceAppCheck: true\}\)\.https\.onCall/],
    ["delivery-tracking.js", /exports\.updateDeliveryTrackingStatus\s*=\s*functions\.runWith\(\{enforceAppCheck: true\}\)\.https\.onCall/],
    ["delivery-tracking.js", /exports\.completeDelivery = functions\.runWith\(\{enforceAppCheck: true\}\)\.https\.onCall/],
    ["delivery-tracking.js", /exports\.updateDeliveryLiveLocation = functions\.runWith\(\{enforceAppCheck: true\}\)\.https\.onCall/],
    ["admin-operations-authority.js", /exports\.adminUpdateIrisCandidateWorkflow = functions\.runWith\(\{enforceAppCheck: true\}\)\.https\.onCall/],
  ];
  for (const [file, pattern] of expectations) {
    assert.match(source(file), pattern, `${file} is missing enforced App Check`);
  }
});

test("public address lookup remains intentionally callable without financial mutation enforcement", () => {
  const freeAddress = source("free-address-search.js");
  assert.match(freeAddress, /const googlePlacesApiKeySecret = defineSecret\("GOOGLE_PLACES_API_KEY"\)/);
  assert.match(freeAddress, /searchFreeUkAddresses = functions\.runWith\(\{[\s\S]*?secrets: \[googlePlacesApiKeySecret\][\s\S]*?\}\)\.https\.onCall/);
  assert.match(freeAddress, /resolveUkAddressPlace = functions\.runWith\(\{[\s\S]*?secrets: \[googlePlacesApiKeySecret\][\s\S]*?\}\)\.https\.onCall/);
});
