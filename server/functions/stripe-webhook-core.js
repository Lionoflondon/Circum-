/* eslint-disable max-len */
"use strict";

function response(status, body) {
  return {status, body};
}

function eventLog(logger, payload) {
  (logger.info || logger.log).call(logger, "stripe_webhook", payload);
}

function createStripeWebhookProcessor(deps) {
  const {
    stripe,
    resolveRuntimeConfig,
    assertEventMode,
    db,
    messaging,
    giftsPayment,
    ratingsTipping,
    stripeRefunds,
    senderBooking,
    businessPayments,
    healthPlus,
    healthMembershipLifecycle,
    rothLedger,
    routeCheckoutSessionCompleted,
    logger = console,
  } = deps;

  return async function processStripeWebhook({rawBody, signature, requestId = ""}) {
    const startedAt = Date.now();
    let runtimeConfig;
    try {
      runtimeConfig = resolveRuntimeConfig();
    } catch (error) {
      logger.error("stripe_webhook_configuration_failed", {requestId, reason: error.message || "invalid_configuration"});
      return response(500, {error: "Webhook configuration unavailable"});
    }

    let event;
    try {
      event = stripe.webhooks.constructEvent(rawBody, signature, runtimeConfig.webhookSecret);
      assertEventMode(event, runtimeConfig);
    } catch (error) {
      logger.warn("stripe_webhook_signature_rejected", {requestId, reason: "invalid_signature"});
      return response(400, {error: "Invalid Stripe webhook signature"});
    }

    const finish = (body, route = "unsupported") => {
      eventLog(logger, {requestId, eventId: event.id, eventType: event.type, route, status: "acknowledged", latencyMs: Date.now() - startedAt});
      return response(200, body);
    };

    if (["customer.subscription.created", "customer.subscription.updated", "customer.subscription.deleted"].includes(event.type)) {
      const result = await healthMembershipLifecycle.handleHealthSubscriptionEvent({db, event});
      return finish({success: true, healthMembership: result}, "health_membership_subscription");
    }
    if (["invoice.paid", "invoice.payment_failed"].includes(event.type)) {
      const result = await healthMembershipLifecycle.handleHealthInvoiceEvent({db, event});
      return finish({success: true, healthMembership: result}, "health_membership_invoice");
    }
    if (event.type === "checkout.session.expired") {
      const giftExpiry = await giftsPayment.handleGiftCheckoutExpired(stripe, event.data.object);
      if (giftExpiry.handled) return finish({success: true, gift: giftExpiry}, "gift_checkout_expired");
    }
    if (event.type.startsWith("charge.dispute.")) {
      const tipDispute = await ratingsTipping.processStripeTipDispute(stripe, event);
      if (tipDispute.handled) return finish({success: true, tipDispute}, "tip_dispute");
    }
    if (event.type === "charge.refunded") {
      const tipRefund = await ratingsTipping.processStripeTipRefund(stripe, event);
      if (tipRefund.handled) return finish({success: true, tipRefund}, "tip_refund");
      const refundResult = await stripeRefunds.syncChargeRefund({db, event});
      return finish({success: true, refund: refundResult}, "payment_refund");
    }
    if (["payment_intent.succeeded", "payment_intent.processing", "payment_intent.payment_failed", "payment_intent.canceled"].includes(event.type)) {
      let giftIntentResult;
      try {
        giftIntentResult = await giftsPayment.handleGiftPaymentIntent(stripe, event.data.object, event.id);
      } catch (error) {
        logger.error("gift_payment_intent_failed", {eventId: event.id, errorType: error.name || "Error"});
        return response(500, {success: false, error: "gift_payment_intent_failed"});
      }
      if (giftIntentResult && giftIntentResult.handled) return finish({success: true, gift: giftIntentResult}, "gift_payment_intent");
      const tipResult = await ratingsTipping.processStripeTipIntent(stripe, event.data.object);
      if (tipResult && tipResult.handled) return finish({success: true, tip: tipResult}, "tip_payment_intent");
      let senderIntentResult;
      try {
        senderIntentResult = await senderBooking.handleSenderPaymentIntent(stripe, event.data.object, event.id);
      } catch (error) {
        logger.error("sender_payment_intent_failed", {eventId: event.id, errorType: error.name || "Error"});
        return response(500, {success: false, error: "sender_payment_intent_failed"});
      }
      if (senderIntentResult && senderIntentResult.handled) return finish({success: true, sender: senderIntentResult}, "sender_payment_intent");
    }
    if (event.type === "charge.succeeded") {
      const metadata = event.data.object.metadata || {};
      if (metadata.pushToken) {
        await messaging.send({
          apns: {payload: {aps: {"content-available": 1}}},
          data: {type: "payment", data: JSON.stringify({metadata, success: true})},
          token: metadata.pushToken,
        }).catch((error) => logger.warn("stripe_payment_notification_failed", {eventId: event.id, reason: error.message || "send_failed"}));
      }
      return finish({success: true}, "charge_succeeded");
    }
    if (event.type === "checkout.session.completed") {
      const session = event.data.object;
      let membershipResult;
      let routed;
      try {
        membershipResult = await healthMembershipLifecycle.handleHealthMembershipCheckoutSession({db, session, event});
        routed = await routeCheckoutSessionCompleted(session, event.id, {
          businessPayments,
          giftsPayment,
          healthPlus,
          rothLedger,
          senderBooking: {handleSenderCheckoutSession: (value, eventId) => senderBooking.handleSenderCheckoutSession(stripe, value, eventId)},
          logger,
        });
      } catch (error) {
        logger.error("checkout_finalization_failed", {eventId: event.id, errorType: error.name || "Error"});
        return response(500, {success: false, error: "checkout_finalization_failed"});
      }
      const metadata = session.metadata || {};
      if (metadata.pushToken) {
        await messaging.send({
          apns: {payload: {aps: {"content-available": 1}}},
          data: {type: "payment", data: JSON.stringify({metadata, success: true})},
          token: metadata.pushToken,
        }).catch((error) => logger.warn("stripe_checkout_notification_failed", {eventId: event.id, reason: error.message || "send_failed"}));
      }
      return finish({success: true, membership: membershipResult, checkout: routed}, "checkout_session_completed");
    }
    return finish({success: true, unsupported: true}, "unsupported");
  };
}

module.exports = {createStripeWebhookProcessor};
