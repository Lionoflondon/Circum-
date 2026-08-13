/* eslint-disable require-jsdoc */
const {
  normalizeOrigin,
  senderAppCancelUrl,
} = require("./app-stripe-return-guard");

function selectedGiftBudgetGbp(gift) {
  return Number(
    gift.selectedBudgetGbp ||
    gift.grossGiftBudget ||
    gift.grossBudget ||
    gift.budget ||
    0,
  );
}

function giftReturnUrls({giftDraftId, source, origin, config = {}}) {
  if (source === "sender_mobile") {
    const base = normalizeOrigin(origin);
    return {
      successUrl: `${base}/#/sender-mobile/gifts/confirmation?giftDraftId=${giftDraftId}&payment=success&session_id={CHECKOUT_SESSION_ID}`,
      cancelUrl: senderAppCancelUrl(null, {
        gift_payment: "cancelled",
        giftDraftId,
      }),
    };
  }
  const baseUrl = "https://circumuk.com/?app=gifts";
  return {
    successUrl: config.success_url || `${baseUrl}&gift_payment=success&giftDraftId=${giftDraftId}&session_id={CHECKOUT_SESSION_ID}`,
    cancelUrl: config.cancel_url || `${baseUrl}&gift_payment=cancelled&giftDraftId=${giftDraftId}`,
  };
}

function giftPaymentMethodFromSplit(split = {}) {
  if (Number(split.walletContributionGbp || 0) <= 0) return "card";
  return Number(split.remainingGbp || 0) > 0 ? "roth_card" : "roth";
}

function normalizeSelfGiftFrequency(value) {
  const normalized = `${value || "one_time"}`.trim().toLowerCase();
  if (["monthly", "month"].includes(normalized)) return "monthly";
  if (["quarterly", "quarter", "every_4_months"].includes(normalized)) return "quarterly";
  return "one_time";
}

function stripeModeForSelfGiftFrequency(value) {
  return normalizeSelfGiftFrequency(value) === "one_time" ? "payment" : "subscription";
}

function subscriptionIntervalForSelfGiftFrequency(value) {
  const frequency = normalizeSelfGiftFrequency(value);
  if (frequency === "monthly") {
    return {interval: "month", interval_count: 1};
  }
  if (frequency === "quarterly") {
    return {interval: "month", interval_count: 4};
  }
  return null;
}

function giftCheckoutMode(gift = {}) {
  const giftType = `${gift.giftType || gift.giftMode || ""}`.trim().toLowerCase();
  if (!["send_to_me", "myself", "self"].includes(giftType)) return "payment";
  return stripeModeForSelfGiftFrequency(gift.selfGiftFrequency);
}

function giftPaymentStatusForStripeMode(mode, stripeStatus) {
  const normalizedMode = `${mode || "payment"}`.trim().toLowerCase();
  const normalizedStatus = `${stripeStatus || ""}`.trim().toLowerCase();
  if (normalizedMode === "subscription") {
    return ["active", "trialing"].includes(normalizedStatus) ? "active" : "pending";
  }
  return normalizedStatus === "paid" || normalizedStatus === "succeeded" ? "paid" : "payment_pending";
}

module.exports = {
  giftCheckoutMode,
  giftPaymentMethodFromSplit,
  giftPaymentStatusForStripeMode,
  giftReturnUrls,
  normalizeSelfGiftFrequency,
  selectedGiftBudgetGbp,
  stripeModeForSelfGiftFrequency,
  subscriptionIntervalForSelfGiftFrequency,
};
