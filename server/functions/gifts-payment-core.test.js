const test = require("node:test");
const assert = require("node:assert/strict");
const {
  giftReturnUrls,
  selectedGiftBudgetGbp,
} = require("./gifts-payment-core");
const {calculateWalletCheckout} = require("./wallet-core");

test("gift checkout charges selected budget in GBP pence when Roth is off", () => {
  const selectedBudget = selectedGiftBudgetGbp({
    selectedBudgetGbp: 1500,
    grossGiftBudget: 1280.66,
    grossBudget: 1280.66,
    budget: 1280.66,
  });
  const split = calculateWalletCheckout({
    orderTotalGbp: selectedBudget,
    walletBalanceGbp: 0,
    selectedCurrency: "gbp",
  });
  assert.equal(selectedBudget, 1500);
  assert.equal(split.walletContributionGbp, 0);
  assert.equal(split.remainingGbp, 1500);
  assert.equal(split.stripeAmountMinor, 150000);
});

test("gift checkout charges remaining GBP pence when Roth is explicitly applied", () => {
  const split = calculateWalletCheckout({
    orderTotalGbp: 1500,
    walletBalanceGbp: 200,
    selectedCurrency: "gbp",
  });
  assert.equal(split.walletContributionGbp, 200);
  assert.equal(split.remainingGbp, 1300);
  assert.equal(split.stripeAmountMinor, 130000);
});

test("sender mobile gifts checkout returns to sender mobile hash routes", () => {
  const urls = giftReturnUrls({
    giftDraftId: "draft_123",
    source: "sender_mobile",
    origin: "https://circum-app-2797c.web.app",
  });
  assert.equal(
    urls.successUrl,
    "https://circum-app-2797c.web.app/#/sender-mobile/gifts/confirmation?giftDraftId=draft_123&payment=success&session_id={CHECKOUT_SESSION_ID}",
  );
  assert.equal(
    urls.cancelUrl,
    "https://circum-app-2797c.web.app/#/sender-mobile/gifts/payment?giftDraftId=draft_123&payment=cancelled",
  );
});

test("web gifts checkout keeps web gifts return routing", () => {
  const urls = giftReturnUrls({giftDraftId: "draft_123", source: "web"});
  assert.equal(
    urls.successUrl,
    "https://circumuk.com/?app=gifts&gift_payment=success&giftDraftId=draft_123&session_id={CHECKOUT_SESSION_ID}",
  );
  assert.equal(
    urls.cancelUrl,
    "https://circumuk.com/?app=gifts&gift_payment=cancelled&giftDraftId=draft_123",
  );
});
