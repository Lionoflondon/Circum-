/* eslint-disable require-jsdoc */

async function routeCheckoutSessionCompleted(
    sessionData,
    eventId,
    deps = {},
) {
  const metadata = sessionData && sessionData.metadata ?
    sessionData.metadata :
    {};
  const type = `${metadata.type || ""}`;
  const logger = deps.logger || console;

  if (type === "business_roth_purchase" ||
      type === "business_invoice_payment") {
    if (!deps.businessPayments ||
        typeof deps.businessPayments.handleBusinessCheckoutSession !==
        "function") {
      throw new Error("business checkout finalizer unavailable");
    }
    await deps.businessPayments.handleBusinessCheckoutSession(
        sessionData,
        eventId,
    );
    return {handled: true, type};
  }

  if (type === "wallet_top_up") {
    if (!deps.rothLedger ||
        typeof deps.rothLedger.recordWalletTopUpFromStripeSession !==
        "function") {
      throw new Error("wallet top-up finalizer unavailable");
    }
    await deps.rothLedger.recordWalletTopUpFromStripeSession(
        sessionData,
        eventId,
    );
    return {handled: true, type};
  }

  if (type === "sender_delivery_payment") {
    if (!deps.senderBooking ||
        typeof deps.senderBooking.handleSenderCheckoutSession !==
        "function") {
      throw new Error("sender checkout finalizer unavailable");
    }
    await deps.senderBooking.handleSenderCheckoutSession(
        sessionData,
        eventId,
    );
    return {handled: true, type};
  }

  if (type === "gift_experience") {
    if (!deps.giftsPayment ||
        typeof deps.giftsPayment.finalizeGiftPaymentFromCheckoutSession !==
        "function") {
      throw new Error("gift checkout finalizer unavailable");
    }
    await deps.giftsPayment.finalizeGiftPaymentFromCheckoutSession({
      giftDraftId: metadata.giftDraftId,
      session: sessionData,
      eventId,
    });
    return {handled: true, type};
  }

  if (type === "health_plus_payment" || metadata.feature === "health_plus") {
    if (!deps.healthPlus ||
        typeof deps.healthPlus.handleHealthPlusCheckoutSession !==
        "function") {
      throw new Error("health plus checkout finalizer unavailable");
    }
    await deps.healthPlus.handleHealthPlusCheckoutSession(
        sessionData,
        eventId,
    );
    return {handled: true, type: type || "health_plus_payment"};
  }

  logger.info(
      "Stripe checkout session completed with no registered finalizer",
      {
        eventId,
        sessionId: sessionData && sessionData.id ? sessionData.id : null,
        type: type || null,
      },
  );
  return {handled: false, type};
}

module.exports = {
  routeCheckoutSessionCompleted,
};
