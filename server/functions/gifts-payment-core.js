/* eslint-disable require-jsdoc */
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
    const base = `${origin || "https://circum-app-2797c.web.app"}`.replace(/\/+$/, "");
    return {
      successUrl: `${base}/#/sender-mobile/gifts/confirmation?giftDraftId=${giftDraftId}&payment=success&session_id={CHECKOUT_SESSION_ID}`,
      cancelUrl: `${base}/#/sender-mobile/gifts/payment?giftDraftId=${giftDraftId}&payment=cancelled`,
    };
  }
  const baseUrl = "https://circumuk.com/?app=gifts";
  return {
    successUrl: config.success_url || `${baseUrl}&gift_payment=success&giftDraftId=${giftDraftId}&session_id={CHECKOUT_SESSION_ID}`,
    cancelUrl: config.cancel_url || `${baseUrl}&gift_payment=cancelled&giftDraftId=${giftDraftId}`,
  };
}

module.exports = {
  giftReturnUrls,
  selectedGiftBudgetGbp,
};
