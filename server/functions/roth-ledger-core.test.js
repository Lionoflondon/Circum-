const test = require("node:test");
const assert = require("node:assert/strict");
const {
  BALANCE_TYPES,
  LEDGER_EVENTS,
  TRANSACTION_TYPES,
  canWithdraw,
  isRothCreditWithdrawable,
  ledgerTransactionRecord,
  nextBalance,
  senderWalletRecord,
} = require("./roth-ledger-core");

test("Roth credit is not withdrawable", () => {
  assert.equal(isRothCreditWithdrawable(), false);
  assert.equal(canWithdraw(BALANCE_TYPES.rothCredit), false);
  assert.equal(canWithdraw(BALANCE_TYPES.pendingEarnings), false);
  assert.equal(canWithdraw(BALANCE_TYPES.availableEarnings), true);
});

test("Roth credit cannot go negative unless reversal is explicit", () => {
  assert.throws(() => nextBalance({
    balanceBefore: 10,
    amount: -20,
    type: TRANSACTION_TYPES.adminDebit,
  }), /cannot go negative/);
  assert.equal(nextBalance({
    balanceBefore: 10,
    amount: -20,
    type: TRANSACTION_TYPES.reversal,
  }), -10);
});

test("sender Roth wallet uses canonical Gifts-ready fields", () => {
  const wallet = senderWalletRecord({
    walletId: "wallet-1",
    userId: "sender-1",
    email: "Sender@Example.com",
    balance: 200,
    createdAt: "now",
  });
  assert.equal(wallet.walletType, "sender");
  assert.equal(wallet.email, "sender@example.com");
  assert.equal(wallet.balance, 200);
  assert.equal(wallet.currencyEquivalent, "GBP");
});

test("Roth gift debit and refund ledger records are auditable", () => {
  const debit = ledgerTransactionRecord({
    transactionId: "tx-debit",
    walletId: "wallet-1",
    userId: "sender-1",
    email: "sender@example.com",
    type: TRANSACTION_TYPES.giftPaymentDebit,
    direction: "debit",
    amount: 50,
    balanceBefore: 200,
    source: "gifts",
    referenceType: "giftPaymentDraft",
    referenceId: "gift-1",
    reason: "Gift payment Roth debit.",
    createdBy: "system",
  });
  assert.equal(debit.balanceAfter, 150);
  assert.equal(debit.direction, "debit");

  const refund = ledgerTransactionRecord({
    transactionId: "tx-refund",
    walletId: "wallet-1",
    userId: "sender-1",
    email: "sender@example.com",
    type: TRANSACTION_TYPES.refundCredit,
    direction: "credit",
    amount: 50,
    balanceBefore: 150,
    source: "gifts",
    referenceType: "giftPaymentDraft",
    referenceId: "gift-1",
    reason: "Refund Roth after failed card payment.",
    createdBy: "system",
  });
  assert.equal(refund.balanceAfter, 200);
  assert.equal(LEDGER_EVENTS.paymentRefunded, "roth_payment_refunded");
  assert.equal(LEDGER_EVENTS.paymentFailed, "roth_payment_failed");
});
