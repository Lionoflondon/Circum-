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
});

test("sender app gifts checkout returns to the Sender app host", () => {
  const urls = giftReturnUrls({
    giftDraftId: "draft_123",
    returnOwner: "sender_app",
  });
  assert.equal(
    urls.successUrl,
    "https://circum-app-2797c.web.app/?app=gifts&gift_payment=success&giftDraftId=draft_123&session_id={CHECKOUT_SESSION_ID}",
  );
  assert.equal(
    urls.cancelUrl,
    "https://circum-app-2797c.web.app/?app=gifts&gift_payment=cancelled&giftDraftId=draft_123",
  );
});

test("sender app campaign checkout returns to the Sender app host", () => {
  const urls = giftReturnUrls({
    giftDraftId: "draft_campaign",
    returnOwner: "sender_app",
  });
  assert.match(urls.successUrl, /^https:\/\/circum-app-2797c\.web\.app\//);
  assert.match(urls.cancelUrl, /^https:\/\/circum-app-2797c\.web\.app\//);
  assert.doesNotMatch(urls.successUrl, /circumuk\.com/);
  assert.doesNotMatch(urls.cancelUrl, /circumuk\.com/);
});

test("cancelled campaign checkout retry preserves its participant linkage", () => {
  const source = require("node:fs").readFileSync(
      require("node:path").join(__dirname, "gifts-payment.js"),
      "utf8",
  );
  assert.match(source, /gift\.campaignParticipantId/);
  assert.match(source, /text\(participant\.paymentDraftId\) !== giftDraftId/);
  assert.match(source, /collection\("giftCampaignParticipants"\)\.doc\(campaignParticipantId\)\.set/);
  assert.match(source, /campaignParticipantId: campaignParticipantId \|\| null/);
});

test("gift return URLs ignore caller and runtime URL overrides", () => {
  const appUrls = giftReturnUrls({
    giftDraftId: "draft_override",
    returnOwner: "sender_app",
    origin: "https://attacker.example",
    config: {
      success_url: "https://attacker.example/success",
      cancel_url: "https://attacker.example/cancel",
    },
  });
  const websiteUrls = giftReturnUrls({
    giftDraftId: "draft_override",
    returnOwner: "website",
    origin: "https://attacker.example",
    config: {
      success_url: "https://attacker.example/success",
      cancel_url: "https://attacker.example/cancel",
    },
  });

  for (const url of Object.values(appUrls)) {
    assert.match(url, /^https:\/\/circum-app-2797c\.web\.app\//);
    assert.doesNotMatch(url, /attacker\.example/);
  }
  for (const url of Object.values(websiteUrls)) {
    assert.match(url, /^https:\/\/circumuk\.com\//);
    assert.doesNotMatch(url, /attacker\.example/);
  }
});

test("web gifts checkout keeps web gifts return routing", () => {
  const urls = giftReturnUrls({
    giftDraftId: "draft_123",
    returnOwner: "website",
  });
  assert.equal(
    urls.successUrl,
    "https://circumuk.com/gifts?gift_payment=success&giftDraftId=draft_123&session_id={CHECKOUT_SESSION_ID}",
  );
  assert.equal(
    urls.cancelUrl,
    "https://circumuk.com/gifts?gift_payment=cancelled&giftDraftId=draft_123",
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
