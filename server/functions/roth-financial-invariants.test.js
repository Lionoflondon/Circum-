/* eslint-disable max-len, require-jsdoc */
"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const {
  TRANSACTION_TYPES,
  ledgerTransactionRecord,
  nextBalance,
  roundMoney,
  walletTransactionView,
} = require("./roth-ledger-core");

const root = __dirname;
const read = (file) => fs.readFileSync(path.join(root, file), "utf8");

function assertSignedInvariant({opening, amount, closing}) {
  assert.equal(roundMoney(opening + amount), roundMoney(closing));
}

function assertBucketInvariant({opening, credits = 0, debits = 0, closing}) {
  assert.equal(roundMoney(opening + credits - debits), roundMoney(closing));
}

test("Roth core ledger records satisfy opening + credits - debits = closing", () => {
  const purchase = ledgerTransactionRecord({
    transactionId: "topup_1",
    walletId: "wallet_user",
    userId: "user_1",
    type: TRANSACTION_TYPES.userTopUp,
    direction: "credit",
    amount: 25,
    balanceBefore: 10,
    source: "purchase",
  });
  assertBucketInvariant({
    opening: purchase.balanceBefore,
    credits: purchase.amount,
    closing: purchase.balanceAfter,
  });

  const spend = ledgerTransactionRecord({
    transactionId: "delivery_1",
    walletId: "wallet_user",
    userId: "user_1",
    type: TRANSACTION_TYPES.checkoutSpend,
    direction: "debit",
    amount: 7.35,
    balanceBefore: purchase.balanceAfter,
    source: "delivery",
  });
  assertBucketInvariant({
    opening: spend.balanceBefore,
    debits: spend.amount,
    closing: spend.balanceAfter,
  });

  const refund = ledgerTransactionRecord({
    transactionId: "refund_1",
    walletId: "wallet_user",
    userId: "user_1",
    type: TRANSACTION_TYPES.refund,
    direction: "credit",
    amount: 2.15,
    balanceBefore: spend.balanceAfter,
    source: "refund",
  });
  assertBucketInvariant({
    opening: refund.balanceBefore,
    credits: refund.amount,
    closing: refund.balanceAfter,
  });
});

test("Roth core signed movements reject accidental negative balances", () => {
  assert.equal(nextBalance({
    balanceBefore: 3,
    amount: 2,
    type: TRANSACTION_TYPES.adminCredit,
  }), 5);
  assert.equal(nextBalance({
    balanceBefore: 3,
    amount: -2,
    type: TRANSACTION_TYPES.checkoutSpend,
  }), 1);
  assert.throws(() => nextBalance({
    balanceBefore: 3,
    amount: -4,
    type: TRANSACTION_TYPES.checkoutSpend,
  }), /cannot go negative/);
});

test("wallet transaction views preserve auditable balance fields", () => {
  const view = walletTransactionView({
    id: "wallet_tip_delivery_1",
    uid: "sender_1",
    amount: -4.5,
    balanceBefore: 20,
    balanceAfter: 15.5,
    type: "delivery_tip",
  });
  assert.equal(view.direction, "debit");
  assert.equal(view.amount, 4.5);
  assertBucketInvariant({
    opening: view.balanceBefore,
    debits: view.amount,
    closing: view.balanceAfter,
  });
});

test("sender Roth writers use signed amounts and store before/after balances", () => {
  const source = read("roth-ledger.js");
  assert.match(source, /balanceAfter = ledgerOnly \? balanceBefore : nextBalance\(\{\s*balanceBefore,\s*amount: roundedAmount,/s);
  assert.match(source, /direction: roundedAmount < 0 \? "debit" : "credit"/);
  assert.match(source, /const after = roundWalletMoney\(before - debit\);/);
  assert.match(source, /amount: -debit,\s*direction: "debit",/s);
  assert.match(source, /balanceBefore: before,\s*balanceAfter: after,/s);
  assert.match(source, /const after = roundWalletMoney\(before \+ value\);/);
  assert.match(source, /type: "gift_card_redemption",\s*amount: value,/s);
  assert.match(source, /balanceBefore: before,\s*balanceAfter: after,/s);
});

test("delivery, Health+ and tips spend Roth through invariant-safe debits", () => {
  const senderBooking = read("sender-booking.js");
  assert.match(senderBooking, /walletBalanceAfter = money\(walletBalanceBefore - rothAppliedAmount\);/);
  assert.match(senderBooking, /amount: -rothAppliedAmount,\s*direction: "debit",/s);
  assert.match(senderBooking, /balanceBefore: walletBalanceBefore,\s*balanceAfter: walletBalanceAfter,/s);

  const health = read("health-plus.js");
  assert.match(health, /rothLedger\.applyWalletDebit\(\{\s*userId: sender\.uid,/s);
  assert.match(health, /type: "health_payment"/);
  assert.match(health, /transactionId: `wallet_health_plus_\$\{bookingId\}`/);

  const tips = read("ratings-tipping.js");
  assert.match(tips, /rothLedger\.applyWalletDebit\(\{\s*userId: sender\.uid/s);
  assert.match(tips, /type: "delivery_tip"/);
  assert.match(tips, /transactionId: `wallet_tip_\$\{delivery\.id\}`/);
});

test("business Roth credits and debits carry previous/resulting balance invariants", () => {
  const source = read("business-payments.js");
  assert.match(source, /const resulting = money\(previous \+ amount\);/);
  assert.match(source, /direction: "credit",\s*amount,/s);
  assert.match(source, /previousBalance: previous,\s*resultingBalance: resulting,/s);
  assert.match(source, /resultingWalletBalance = money\(previousWalletBalance - normalizedRothAmount\);/);
  assert.match(source, /direction: "debit",\s*amount: normalizedRothAmount,/s);
  assert.match(source, /previousBalance: previousWalletBalance,\s*resultingBalance: resultingWalletBalance,/s);
});

test("generic client Roth debit entrypoints are disabled", () => {
  const source = read("roth-ledger.js");
  assert.match(source, /exports\.requestSenderWalletDebit[\s\S]*?Roth is applied only through a verified CIRCUM checkout/);
  assert.match(source, /exports\.applyCheckoutRoth[\s\S]*?Roth is applied only through the canonical payment session/);
});

test("representative Roth lifecycle invariants reconcile by user and business", () => {
  const user = [
    {kind: "purchase", opening: 0, credits: 100, debits: 0, closing: 100},
    {kind: "delivery_spend", opening: 100, credits: 0, debits: 35.92, closing: 64.08},
    {kind: "tip", opening: 64.08, credits: 0, debits: 4, closing: 60.08},
    {kind: "health_plus", opening: 60.08, credits: 0, debits: 12.5, closing: 47.58},
    {kind: "refund", opening: 47.58, credits: 7.5, debits: 0, closing: 55.08},
    {kind: "admin_issue", opening: 55.08, credits: 10, debits: 0, closing: 65.08},
    {kind: "adjustment", opening: 65.08, credits: 0, debits: 5.08, closing: 60},
  ];
  for (const movement of user) {
    assertBucketInvariant(movement);
  }

  const business = [
    {kind: "purchase", opening: 25, credits: 200, debits: 0, closing: 225},
    {kind: "invoice_spend", opening: 225, credits: 0, debits: 80.75, closing: 144.25},
    {kind: "refund", opening: 144.25, credits: 10.25, debits: 0, closing: 154.5},
  ];
  for (const movement of business) {
    assertBucketInvariant(movement);
  }

  assertSignedInvariant({opening: 12.34, amount: 5.66, closing: 18});
  assertSignedInvariant({opening: 18, amount: -3.33, closing: 14.67});
});
