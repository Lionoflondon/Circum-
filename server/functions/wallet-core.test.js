const test = require("node:test");
const assert = require("node:assert/strict");
const {
  calculateWalletCheckout,
  canRedeemGiftCard,
  normalizeEmail,
  normalizeStripeCurrency,
  walletIdForEmail,
} = require("./wallet-core");

test("full wallet payment skips Stripe", () => {
  const split = calculateWalletCheckout({orderTotalGbp: 25, walletBalanceGbp: 40});
  assert.equal(split.walletContributionGbp, 25);
  assert.equal(split.remainingGbp, 0);
  assert.equal(split.stripeRequired, false);
});

test("partial wallet payment charges Stripe for the remainder", () => {
  const split = calculateWalletCheckout({orderTotalGbp: 50, walletBalanceGbp: 20});
  assert.equal(split.walletContributionGbp, 20);
  assert.equal(split.remainingGbp, 30);
  assert.equal(split.stripeRequired, true);
  assert.equal(split.stripeAmountMinor, 3000);
});

test("zero wallet payment charges Stripe for the full amount", () => {
  const split = calculateWalletCheckout({orderTotalGbp: 50, walletBalanceGbp: 0});
  assert.equal(split.walletContributionGbp, 0);
  assert.equal(split.remainingGbp, 50);
  assert.equal(split.stripeRequired, true);
});

test("foreign currency partial wallet payment keeps ledger GBP", () => {
  const split = calculateWalletCheckout({
    orderTotalGbp: 50,
    walletBalanceGbp: 20,
    selectedCurrency: "usd",
  });
  assert.equal(split.orderTotalGbp, 50);
  assert.equal(split.walletContributionGbp, 20);
  assert.equal(split.remainingGbp, 30);
  assert.equal(split.customerPaymentCurrency, "usd");
  assert.equal(split.internalCurrency, "GBP");
  assert.equal(split.estimatedConversion, true);
});

test("unsupported currency falls back to GBP", () => {
  assert.equal(normalizeStripeCurrency("xyz"), "gbp");
  const split = calculateWalletCheckout({
    orderTotalGbp: 10,
    walletBalanceGbp: 0,
    selectedCurrency: "xyz",
  });
  assert.equal(split.customerPaymentCurrency, "gbp");
  assert.equal(split.stripeAmountMinor, 1000);
});

test("gift card redemption requires active unredeemed card", () => {
  assert.equal(canRedeemGiftCard({status: "active", value: 50}), true);
  assert.equal(canRedeemGiftCard({status: "redeemed", value: 50}), false);
  assert.equal(canRedeemGiftCard({status: "active", redeemedBy: "user"}), false);
});

test("email normalization creates one canonical Roth wallet key", () => {
  assert.equal(normalizeEmail("  AyoJason600@GMAIL.COM "), "ayojason600@gmail.com");
  assert.equal(walletIdForEmail("  AyoJason600@GMAIL.COM "), "ayojason600@gmail.com");
});
