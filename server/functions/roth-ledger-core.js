/* eslint-disable max-len */
"use strict";

const BALANCE_TYPES = Object.freeze({
  rothCredit: "rothCredit",
  pendingEarnings: "pendingEarnings",
  availableEarnings: "availableEarnings",
});

const TRANSACTION_TYPES = Object.freeze({
  adminIssue: "admin_issue",
  giftPaymentDebit: "gift_payment_debit",
  refundCredit: "refund_credit",
  adjustment: "adjustment",
  rothCredit: "roth_credit",
  rothDebit: "roth_debit",
  rothSpend: "roth_spend",
  giftCardRedeem: "gift_card_redeem",
  userTopUp: "USER_TOP_UP",
  rewardCredit: "reward_credit",
  referralReward: "referral_reward",
  referralWelcomeReward: "referral_welcome_reward",
  adminCredit: "admin_credit",
  adminDebit: "admin_debit",
  earningsPending: "earnings_pending",
  earningsAvailable: "earnings_available",
  withdrawal: "withdrawal",
  stripePaymentRecord: "stripe_payment_record",
  refundRecord: "refund_record",
  reversal: "reversal",
});

const LEDGER_EVENTS = Object.freeze({
  walletCreated: "roth_wallet_created",
  adminIssued: "roth_admin_issued",
  paymentDebited: "roth_payment_debited",
  paymentRefunded: "roth_payment_refunded",
  paymentFailed: "roth_payment_failed",
});

function roundMoney(value) {
  const amount = Number(value || 0);
  if (!Number.isFinite(amount)) return 0;
  return Math.round(amount * 100) / 100;
}

function assertBalanceType(balanceType) {
  if (!Object.values(BALANCE_TYPES).includes(balanceType)) {
    throw new Error(`Unsupported Roth balance type: ${balanceType}`);
  }
}

function assertTransactionType(type) {
  if (!Object.values(TRANSACTION_TYPES).includes(type)) {
    throw new Error(`Unsupported Roth transaction type: ${type}`);
  }
}

function canWithdraw(balanceType) {
  return balanceType === BALANCE_TYPES.availableEarnings;
}

function isRothCreditWithdrawable() {
  return false;
}

function nextBalance({balanceBefore, amount, allowNegative = false, type}) {
  const after = roundMoney(balanceBefore + amount);
  if (after < 0 && !allowNegative && type !== TRANSACTION_TYPES.reversal) {
    throw new Error("Roth ledger balances cannot go negative without an auditable reversal.");
  }
  return after;
}

function senderWalletRecord({walletId, userId, email, balance = 0, createdAt = null, updatedAt = null}) {
  return {
    walletId,
    userId,
    email: `${email || ""}`.trim().toLowerCase(),
    walletType: "sender",
    balance: roundMoney(balance),
    currencyEquivalent: "GBP",
    createdAt,
    updatedAt: updatedAt || createdAt,
  };
}

function ledgerTransactionRecord({
  transactionId,
  walletId,
  userId,
  email,
  type,
  direction,
  amount,
  balanceBefore,
  source,
  referenceType,
  referenceId,
  reason,
  createdBy,
  createdAt = null,
}) {
  assertTransactionType(type);
  const roundedAmount = roundMoney(amount);
  const signedAmount = direction === "debit" ? -Math.abs(roundedAmount) : Math.abs(roundedAmount);
  const balanceAfter = nextBalance({
    balanceBefore: roundMoney(balanceBefore),
    amount: signedAmount,
    type,
  });
  return {
    transactionId,
    walletId,
    userId,
    email: `${email || ""}`.trim().toLowerCase(),
    type,
    direction,
    amount: roundedAmount,
    balanceBefore: roundMoney(balanceBefore),
    balanceAfter,
    source,
    referenceType,
    referenceId,
    reason,
    createdBy,
    createdAt,
  };
}

module.exports = {
  BALANCE_TYPES,
  LEDGER_EVENTS,
  TRANSACTION_TYPES,
  roundMoney,
  assertBalanceType,
  assertTransactionType,
  canWithdraw,
  isRothCreditWithdrawable,
  ledgerTransactionRecord,
  nextBalance,
  senderWalletRecord,
};
