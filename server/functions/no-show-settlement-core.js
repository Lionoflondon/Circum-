"use strict";

const AMOUNTS = Object.freeze({customerPence: 700, riderPence: 400, platformPence: 300});
const MAX_ATTEMPTS = 5;
const RETRY_DELAYS_MS = Object.freeze([5, 15, 60, 240].map((minutes) => minutes * 60 * 1000));

function text(value) {
  return `${value || ""}`.trim();
}

function authorityDecision({delivery = {}, paymentSession = {}, paymentIntent = {}} = {}) {
  const senderId = text(delivery.senderId || delivery.userId);
  const sessionId = text(delivery.paymentSessionId);
  const intentId = text(delivery.stripePaymentIntentId);
  const customerId = text(delivery.stripeCustomerId);
  const intentMetadata = paymentIntent.metadata || {};
  const paymentMethodId = text(paymentIntent.payment_method && paymentIntent.payment_method.id || paymentIntent.payment_method);
  const explicitFutureUse = paymentIntent.setup_future_usage === "off_session" ||
    paymentSession.futureUsageAuthorized === true;
  const linked = sessionId && paymentSession.userId === senderId &&
    text(paymentSession.stripePaymentIntentId) === intentId &&
    text(paymentSession.stripeCustomerId) === customerId &&
    text(intentMetadata.paymentSessionId) === sessionId &&
    text(intentMetadata.userId) === senderId;
  if (!senderId || !sessionId || !intentId || !customerId) return {allowed: false, reason: "missing_payment_authority"};
  if (!linked) return {allowed: false, reason: "payment_authority_mismatch"};
  if (!explicitFutureUse) return {allowed: false, reason: "off_session_authority_unproven"};
  if (!paymentMethodId) return {allowed: false, reason: "payment_method_unavailable"};
  if (text(paymentIntent.customer && paymentIntent.customer.id || paymentIntent.customer) !== customerId) {
    return {allowed: false, reason: "payment_customer_mismatch"};
  }
  return {allowed: true, customerId, paymentMethodId, paymentIntentId: intentId, sessionId};
}

function pendingFinancial(deliveryId, riderId) {
  return {
    settlementId: `no_show_${deliveryId}`,
    idempotencyKey: `no_show_settlement_${deliveryId}`,
    deliveryId,
    riderId,
    state: "SETTLEMENT_PENDING",
    settlementStatus: "pending_collection",
    customerCharge: 7,
    riderCompensation: 4,
    platformAmount: 3,
    customerCollected: 0,
    riderCredited: 0,
    platformRealized: 0,
    attemptCount: 0,
  };
}

function retryDecision(attemptCount, now = Date.now()) {
  const attempts = Math.max(1, Number(attemptCount) || 1);
  if (attempts >= MAX_ATTEMPTS) return {exhausted: true, nextAttemptAt: null};
  const delay = RETRY_DELAYS_MS[Math.min(attempts - 1, RETRY_DELAYS_MS.length - 1)];
  return {exhausted: false, nextAttemptAt: new Date(now + delay)};
}

module.exports = {AMOUNTS, MAX_ATTEMPTS, RETRY_DELAYS_MS, authorityDecision, pendingFinancial, retryDecision};
