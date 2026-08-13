/* eslint-disable max-len, require-jsdoc */
"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

function source(file) {
  return fs.readFileSync(path.join(__dirname, file), "utf8");
}

function assertCallableRequiresAppCheck(file, exportName) {
  const contents = source(file);
  assert.match(contents, /require\("\.\/callable-guard"\)/, `${file} imports callable guard`);
  const exportPattern = new RegExp(`exports\\.${exportName}\\s*=`);
  const constPattern = new RegExp(`const\\s+${exportName}\\s*=`);
  const match = exportPattern.exec(contents) || constPattern.exec(contents);
  assert.ok(match, `${file} defines ${exportName}`);
  const bodyStart = contents.indexOf("{", match.index);
  assert.notEqual(bodyStart, -1, `${exportName} has a callable body`);
  const firstBodyLines = contents.slice(bodyStart, bodyStart + 260);
  assert.match(firstBodyLines, /requireAppCheck\(context\);/, `${exportName} requires App Check before material work`);
}

test("Sender booking and payment callables require App Check", () => {
  [
    "createSenderBookingQuote",
    "createSenderPaymentSession",
    "createSenderPaidDelivery",
    "finalizeSenderWebCheckout",
  ].forEach((name) => assertCallableRequiresAppCheck("sender-booking.js", name));
});

test("Rider dispatch, tracking, lifecycle, and adjudication callables require App Check", () => {
  assertCallableRequiresAppCheck("accept-ride-requests.js", "acceptRideRequests");
  [
    "updateDeliveryTrackingStatus",
    "updateDeliveryLiveLocation",
  ].forEach((name) => assertCallableRequiresAppCheck("delivery-tracking.js", name));
  [
    "recordDeliveryEvidence",
    "getDeliveryEvidenceAccess",
  ].forEach((name) => assertCallableRequiresAppCheck("delivery-evidence.js", name));
  [
    "requestSenderCancellation",
    "previewSenderCancellation",
    "recordRiderArrival",
    "recordArrivalZoneCheck",
    "recordCustomerArrivalResponse",
    "reportWaitingContext",
    "markRiderNoShow",
  ].forEach((name) => assertCallableRequiresAppCheck("delivery-policy.js", name));
  [
    "reportLoadDiscrepancy",
    "reviewDeliveryAdjustment",
    "cancelAdjustedCollection",
    "createDeliveryAdjustmentPayment",
    "finalizeDeliveryAdjustmentPayment",
  ].forEach((name) => assertCallableRequiresAppCheck("delivery-adjustments.js", name));
});

test("Roth wallet mutation callables require App Check", () => {
  [
    "initialiseSenderWallet",
    "getSenderWallet",
    "getSenderWalletTransactions",
    "completeSenderWalletOnboarding",
    "requestSenderWalletDebit",
    "requestSenderWalletRefund",
    "createWalletTopUp",
    "applyCheckoutRoth",
    "issueRothToWallets",
    "issueRothCredit",
    "debitRothCredit",
    "setWalletFrozen",
    "redeemGiftCard",
  ].forEach((name) => assertCallableRequiresAppCheck("roth-ledger.js", name));
});

test("Sender saved-card and referral callables require App Check", () => {
  [
    "listSenderPaymentMethods",
    "createSenderSetupIntent",
    "createSenderSetupCheckoutSession",
    "detachSenderPaymentMethod",
    "setDefaultSenderPaymentMethod",
    "saveSenderCheckoutPreference",
  ].forEach((name) => assertCallableRequiresAppCheck("sender-finance.js", name));
  [
    "ensureReferralCode",
    "getReferralDashboard",
    "attachReferralCode",
    "activateReferral",
  ].forEach((name) => assertCallableRequiresAppCheck("referrals.js", name));
});

test("Sender profile photo association requires App Check", () => {
  assertCallableRequiresAppCheck("sender-account.js", "updateSenderProfilePhoto");
});

test("Admin delivery intervention callables require App Check", () => {
  assertCallableRequiresAppCheck("admin-governance.js", "adminGovernanceAction");
  [
    "adminRecordAuditEntry",
    "adminDuplicateDelivery",
    "adminUpdateDeliveryOperation",
    "adminArchiveDelivery",
  ].forEach((name) => assertCallableRequiresAppCheck("admin-operations-authority.js", name));
  assertCallableRequiresAppCheck("stale-delivery.js", "resolveStaleDeliveryLock");
});
