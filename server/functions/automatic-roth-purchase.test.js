/* eslint-disable max-len */
"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const test = require("node:test");

const rothLedgerSource = fs.readFileSync("roth-ledger.js", "utf8");
const businessPaymentsSource = fs.readFileSync("business-payments.js", "utf8");
const adminSource = fs.readFileSync("../../lib/app/admin/admin_phase1_shell.dart", "utf8");

test("individual Roth purchases are finalized from verified Stripe amount only", () => {
  assert.match(rothLedgerSource, /verifiedStripeRothPurchase\(sessionData,\s*\{[\s\S]*?ownerId: metadata\.userId \|\| metadata\.uid/);
  assert.match(rothLedgerSource, /const amount = purchase\.rothIssued;/);
  assert.doesNotMatch(rothLedgerSource, /metadata\.amountGbp \|\| Number\(sessionData\.amount_total/);
  assert.match(rothLedgerSource, /client_reference_id: identity\.walletId/);
});

test("business Roth purchases are finalized from verified Stripe amount only", () => {
  assert.match(businessPaymentsSource, /verifiedStripeRothPurchase\(sessionData, \{ownerId: businessId\}\)/);
  assert.match(businessPaymentsSource, /const amount = verifiedPurchase\.rothIssued;/);
  assert.doesNotMatch(businessPaymentsSource, /metadata\.amountGbp \|\| Number\(sessionData\.amount_total/);
  assert.match(businessPaymentsSource, /client_reference_id: businessId/);
});

test("Roth purchase finalizers are idempotent", () => {
  assert.match(rothLedgerSource, /const \[existingLedger, wallet, senderWalletSnap\]/);
  assert.match(rothLedgerSource, /if \(existingLedger\.exists\) return;/);
  assert.match(businessPaymentsSource, /const existingTx = await transaction\.get\(txRef\);/);
  assert.match(businessPaymentsSource, /if \(existingTx\.exists\) return;/);
  assert.match(businessPaymentsSource, /purchaseRecord\.status === "paid" \|\| purchaseRecord\.creditedAt/);
});

test("Roth purchase ledger records expose audit and admin-visible fields", () => {
  for (const field of ["transactionId", "amountGBP", "rothIssued", "currency", "source", "paymentIntentId", "balanceBefore", "balanceAfter"]) {
    assert.match(rothLedgerSource, new RegExp(`${field}:`));
  }
  for (const field of ["transactionId", "amountGBP", "rothIssued", "currency", "source", "paymentIntentId", "previousBalance", "resultingBalance"]) {
    assert.match(businessPaymentsSource, new RegExp(`${field}:`));
  }
  assert.match(adminSource, /collection\('walletTransactions'\)/);
  assert.match(adminSource, /collection\('businessRothPurchases'\)/);
});

test("Roth purchase confirmation notifications are emitted without client balance authority", () => {
  assert.match(rothLedgerSource, /type: "roth_purchase_completed"/);
  assert.match(businessPaymentsSource, /type: "business_roth_purchase_completed"/);
  assert.match(rothLedgerSource, /type: "roth_purchase_failed"/);
  assert.match(businessPaymentsSource, /type: "business_roth_purchase_failed"/);
  assert.match(businessPaymentsSource, /status: "failed"/);
  assert.doesNotMatch(rothLedgerSource, /exports\.recordWalletTopUpFromStripeSession\s*=\s*functions\.https\.onCall/);
});
