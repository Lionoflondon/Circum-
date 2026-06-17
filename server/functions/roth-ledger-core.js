/* eslint-disable max-len */
"use strict";

const BALANCE_TYPES = Object.freeze({
  rothCredit: "rothCredit",
  pendingEarnings: "pendingEarnings",
  availableEarnings: "availableEarnings",
});

const TRANSACTION_TYPES = Object.freeze({
  rothCredit: "roth_credit",
  rothDebit: "roth_debit",
  rothSpend: "roth_spend",
  giftCardRedeem: "gift_card_redeem",
  userTopUp: "USER_TOP_UP",
  rewardCredit: "reward_credit",
  adminCredit: "admin_credit",
  adminDebit: "admin_debit",
  earningsPending: "earnings_pending",
  earningsAvailable: "earnings_available",
  withdrawal: "withdrawal",
  stripePaymentRecord: "stripe_payment_record",
  refundRecord: "refund_record",
  reversal: "reversal",
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

module.exports = {
  BALANCE_TYPES,
  TRANSACTION_TYPES,
  roundMoney,
  assertBalanceType,
  assertTransactionType,
  canWithdraw,
  isRothCreditWithdrawable,
  nextBalance,
};
