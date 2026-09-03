"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");

test("Sender payment callable wrapper enforces Firebase App Check", () => {
  const wrapper = fs.readFileSync("sender-app-check.js", "utf8");
  assert.match(wrapper, /runWith\(\{\.\.\.options, enforceAppCheck:\s*true\}\)/);
});

test("all Sender payment authority callables use the App Check wrapper", () => {
  const booking = fs.readFileSync("sender-booking.js", "utf8");
  const finance = fs.readFileSync("sender-finance.js", "utf8");
  for (const name of [
    "getSenderRothBalance",
    "createSenderBookingQuote",
    "createSenderPaymentSession",
    "createSenderPaidDelivery",
    "finalizeSenderWebCheckout",
  ]) {
    assert.match(booking, new RegExp(`exports\\.${name}[^=]*=[\\s\\S]*?senderPaymentCallable`), name);
  }
  for (const name of [
    "listSenderPaymentMethods",
    "createSenderSetupIntent",
    "detachSenderPaymentMethod",
    "setDefaultSenderPaymentMethod",
    "saveSenderCheckoutPreference",
  ]) {
    assert.match(finance, new RegExp(`exports\\.${name}[^=]*=[\\s\\S]*?senderPaymentCallable`), name);
  }
});

test("Sender Roth, tip, and Gift payment callables enforce App Check", () => {
  const roth = fs.readFileSync("roth-ledger.js", "utf8");
  const tips = fs.readFileSync("ratings-tipping.js", "utf8");
  const gifts = fs.readFileSync("gifts-payment.js", "utf8");
  for (const name of [
    "initialiseSenderWallet",
    "getSenderWallet",
    "getSenderWalletTransactions",
    "completeSenderWalletOnboarding",
    "requestSenderWalletDebit",
    "requestSenderWalletRefund",
    "createWalletTopUp",
    "applyCheckoutRoth",
    "debitRothCredit",
    "redeemGiftCard",
  ]) {
    assert.match(roth, new RegExp(`exports\\.${name}[^=]*=[\\s\\S]*?senderPaymentCallable`), name);
  }
  assert.match(tips, /function submitTip[\s\S]*?senderPaymentCallable/);
  assert.match(gifts, /exports\.createGiftPayment[\s\S]*?senderPaymentCallable/);
  assert.match(gifts, /exports\.finalizeGiftPayment[\s\S]*?senderPaymentCallable/);
});

test("Sender delivery adjustment payment callables enforce App Check", () => {
  const adjustments = fs.readFileSync("delivery-adjustments.js", "utf8");
  for (const name of [
    "createDeliveryAdjustmentPayment",
    "finalizeDeliveryAdjustmentPayment",
  ]) {
    assert.match(
        adjustments,
        new RegExp(`exports\\.${name}[^=]*=[\\s\\S]*?senderPaymentCallable`),
        name,
    );
  }
});
