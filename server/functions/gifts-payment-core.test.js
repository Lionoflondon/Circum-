const test = require("node:test");
const assert = require("node:assert/strict");
const {
  giftCheckoutMode,
  giftPaymentMethodFromSplit,
  giftPaymentStatusForStripeMode,
  giftReturnUrls,
  normalizeSelfGiftFrequency,
  selectedGiftBudgetGbp,
  stripeModeForSelfGiftFrequency,
  subscriptionIntervalForSelfGiftFrequency,
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

test("gift checkout persists canonical payment method labels", () => {
  assert.equal(giftPaymentMethodFromSplit({
    walletContributionGbp: 0,
    remainingGbp: 1500,
  }), "card");
  assert.equal(giftPaymentMethodFromSplit({
    walletContributionGbp: 200,
    remainingGbp: 1300,
  }), "roth_card");
  assert.equal(giftPaymentMethodFromSplit({
    walletContributionGbp: 1500,
    remainingGbp: 0,
  }), "roth");
  assert.equal(giftPaymentMethodFromSplit({
    walletContributionGbp: 0,
    remainingGbp: 20,
  }, "apple_pay"), "apple_pay");
  assert.equal(giftPaymentMethodFromSplit({
    walletContributionGbp: 7,
    remainingGbp: 13,
  }, "apple_pay"), "roth_apple_pay");
  assert.equal(giftPaymentMethodFromSplit({
    walletContributionGbp: 7,
    remainingGbp: 13,
  }, "google_pay"), "roth_google_pay");
  assert.equal(giftPaymentMethodFromSplit({
    walletContributionGbp: 7,
    remainingGbp: 13,
  }, "saved_card"), "roth_saved_card");
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

test("send to me frequency controls Stripe payment versus subscriptions", () => {
  assert.equal(normalizeSelfGiftFrequency("one_time"), "one_time");
  assert.equal(normalizeSelfGiftFrequency("monthly"), "monthly");
  assert.equal(normalizeSelfGiftFrequency("quarterly"), "quarterly");
  assert.equal(stripeModeForSelfGiftFrequency("one_time"), "payment");
  assert.equal(stripeModeForSelfGiftFrequency("monthly"), "subscription");
  assert.equal(stripeModeForSelfGiftFrequency("quarterly"), "subscription");
  assert.deepEqual(subscriptionIntervalForSelfGiftFrequency("monthly"), {
    interval: "month",
    interval_count: 1,
  });
  assert.deepEqual(subscriptionIntervalForSelfGiftFrequency("quarterly"), {
    interval: "month",
    interval_count: 4,
  });
});

test("only send to me recurring gifts create subscription checkout mode", () => {
  assert.equal(giftCheckoutMode({
    giftType: "send_to_me",
    selfGiftFrequency: "monthly",
  }), "subscription");
  assert.equal(giftCheckoutMode({
    giftType: "send_to_me",
    selfGiftFrequency: "quarterly",
  }), "subscription");
  assert.equal(giftCheckoutMode({
    giftType: "send_to_me",
    selfGiftFrequency: "one_time",
  }), "payment");
  assert.equal(giftCheckoutMode({
    giftType: "send_to_someone",
    selfGiftFrequency: "monthly",
  }), "payment");
});

test("subscription status is active only after Stripe confirms active state", () => {
  assert.equal(giftPaymentStatusForStripeMode("subscription", "active"), "active");
  assert.equal(giftPaymentStatusForStripeMode("subscription", "trialing"), "active");
  assert.equal(giftPaymentStatusForStripeMode("subscription", "incomplete"), "pending");
  assert.equal(giftPaymentStatusForStripeMode("payment", "paid"), "paid");
});
