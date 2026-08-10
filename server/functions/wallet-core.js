/* eslint-disable max-len */
"use strict";

const SUPPORTED_STRIPE_CURRENCIES = new Set([
  "gbp",
  "usd",
  "eur",
  "cad",
  "aud",
  "nzd",
  "chf",
  "sek",
  "nok",
  "dkk",
  "pln",
  "jpy",
]);

const ZERO_DECIMAL_CURRENCIES = new Set(["jpy"]);

const ESTIMATED_RATES_FROM_GBP = Object.freeze({
  gbp: 1,
  usd: 1.27,
  eur: 1.18,
  cad: 1.74,
  aud: 1.94,
  nzd: 2.08,
  chf: 1.13,
  sek: 12.45,
  nok: 13.45,
  dkk: 8.80,
  pln: 5.10,
  jpy: 201,
});

function roundMoney(value) {
  const amount = Number(value || 0);
  if (!Number.isFinite(amount)) return 0;
  return Math.round(amount * 100) / 100;
}

function normalizeStripeCurrency(currency) {
  const normalized = `${currency || "gbp"}`.trim().toLowerCase();
  return SUPPORTED_STRIPE_CURRENCIES.has(normalized) ? normalized : "gbp";
}

function normalizeEmail(email) {
  return `${email || ""}`.trim().toLowerCase();
}

function walletIdForEmail(email) {
  const normalized = normalizeEmail(email);
  return normalized || null;
}

function minorUnits(amount, currency = "gbp") {
  const normalized = normalizeStripeCurrency(currency);
  const value = Number(amount || 0);
  if (ZERO_DECIMAL_CURRENCIES.has(normalized)) return Math.round(value);
  return Math.round(value * 100);
}

function estimateCurrencyAmountFromGbp(amountGbp, currency = "gbp") {
  const normalized = normalizeStripeCurrency(currency);
  const rate = ESTIMATED_RATES_FROM_GBP[normalized] || 1;
  return roundMoney(Number(amountGbp || 0) * rate);
}

function calculateWalletCheckout({orderTotalGbp, walletBalanceGbp, selectedCurrency = "gbp"}) {
  const total = roundMoney(orderTotalGbp);
  const balance = Math.max(0, roundMoney(walletBalanceGbp));
  if (total < 0) throw new Error("Order total cannot be negative.");
  const walletContributionGbp = roundMoney(Math.min(total, balance));
  const remainingGbp = roundMoney(total - walletContributionGbp);
  const currency = normalizeStripeCurrency(selectedCurrency);
  const customerPaymentAmount = estimateCurrencyAmountFromGbp(remainingGbp, currency);
  return {
    orderTotalGbp: total,
    walletBalanceGbp: balance,
    walletContributionGbp,
    remainingGbp,
    stripeRequired: remainingGbp > 0,
    customerPaymentCurrency: currency,
    customerPaymentAmount,
    stripeAmountMinor: minorUnits(customerPaymentAmount, currency),
    estimatedConversion: currency !== "gbp",
    internalCurrency: "GBP",
  };
}

function walletBalanceValue(record = {}) {
  const value = record.balance == null ? record.rothCredit : record.balance;
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed >= 0 ? roundMoney(parsed) : null;
}

function canonicalSenderWalletBalance({ledgerWallet = null, projectionWallet = null} = {}) {
  const ledgerBalance = ledgerWallet ? walletBalanceValue(ledgerWallet) : null;
  const projectionBalance = projectionWallet ? walletBalanceValue(projectionWallet) : null;
  if (ledgerBalance != null && projectionBalance != null && ledgerBalance !== projectionBalance) {
    throw new Error("Sender wallet balance authority is out of sync.");
  }
  return ledgerBalance == null ? projectionBalance || 0 : ledgerBalance;
}

function canRedeemGiftCard(card) {
  if (!card) return false;
  const status = `${card.status || ""}`.toLowerCase();
  if (status !== "active") return false;
  if (card.redeemedBy || card.redeemedAt) return false;
  const expiresAt = card.expiresAt && typeof card.expiresAt.toMillis === "function" ?
    card.expiresAt.toMillis() :
    Number(card.expiresAt || 0);
  return !expiresAt || expiresAt > Date.now();
}

module.exports = {
  SUPPORTED_STRIPE_CURRENCIES,
  calculateWalletCheckout,
  canonicalSenderWalletBalance,
  canRedeemGiftCard,
  estimateCurrencyAmountFromGbp,
  minorUnits,
  normalizeEmail,
  normalizeStripeCurrency,
  roundMoney,
  walletIdForEmail,
};
