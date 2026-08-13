/* eslint-disable max-len, require-jsdoc */
"use strict";

const functions = require("firebase-functions/v1");

const RETURN_OWNERS = Object.freeze({
  SENDER_APP: "sender_app",
  WEBSITE: "website",
});

const RETURN_FLOWS = Object.freeze({
  BUSINESS_INVOICE: "business_invoice",
  BUSINESS_ROTH: "business_roth",
  GIFT: "gift",
  HEALTH_PLUS: "health_plus",
  SENDER_DELIVERY: "sender_delivery",
  WALLET_TOP_UP: "wallet_top_up",
});

const CHECKOUT_SESSION_ID = "{CHECKOUT_SESSION_ID}";

const FIXED_RETURN_BASES = Object.freeze({
  [RETURN_FLOWS.BUSINESS_INVOICE]: Object.freeze({
    [RETURN_OWNERS.SENDER_APP]: "https://circum-app-2797c.web.app/?app=business&section=invoicing",
    [RETURN_OWNERS.WEBSITE]: "https://circumuk.com/send/business?section=invoicing",
  }),
  [RETURN_FLOWS.BUSINESS_ROTH]: Object.freeze({
    [RETURN_OWNERS.SENDER_APP]: "https://circum-app-2797c.web.app/?app=business&section=invoicing",
    [RETURN_OWNERS.WEBSITE]: "https://circumuk.com/send/business?section=invoicing",
  }),
  [RETURN_FLOWS.GIFT]: Object.freeze({
    [RETURN_OWNERS.SENDER_APP]: "https://circum-app-2797c.web.app/?app=gifts",
    [RETURN_OWNERS.WEBSITE]: "https://circumuk.com/gifts",
  }),
  [RETURN_FLOWS.HEALTH_PLUS]: Object.freeze({
    [RETURN_OWNERS.SENDER_APP]: "https://circum-app-2797c.web.app/?app=health",
    [RETURN_OWNERS.WEBSITE]: "https://circumuk.com/send/health",
  }),
  [RETURN_FLOWS.SENDER_DELIVERY]: Object.freeze({
    [RETURN_OWNERS.SENDER_APP]: "https://circum-app-2797c.web.app/send?app=sender&tab=1",
    [RETURN_OWNERS.WEBSITE]: "https://circumuk.com/send",
  }),
  [RETURN_FLOWS.WALLET_TOP_UP]: Object.freeze({
    [RETURN_OWNERS.SENDER_APP]: "https://circum-app-2797c.web.app/?app=sender&section=wallet",
    [RETURN_OWNERS.WEBSITE]: "https://circumuk.com/send/profile?section=wallet",
  }),
});

function resolveReturnOwner(value) {
  const owner = `${value || ""}`.trim();
  if (!Object.values(RETURN_OWNERS).includes(owner)) {
    throw new functions.https.HttpsError(
        "invalid-argument",
        "returnOwner must be sender_app or website.",
    );
  }
  return owner;
}

function stripeReturnBase(flow, returnOwner) {
  const owner = resolveReturnOwner(returnOwner);
  const byOwner = FIXED_RETURN_BASES[flow];
  if (!byOwner) {
    throw new Error(`Unsupported Stripe return flow: ${flow}`);
  }
  return byOwner[owner];
}

function queryValue(value) {
  if (value === CHECKOUT_SESSION_ID) return value;
  return encodeURIComponent(`${value == null ? "" : value}`);
}

function withQuery(base, entries) {
  const separator = base.includes("?") ? "&" : "?";
  return `${base}${separator}${entries.map(([key, value]) => `${encodeURIComponent(key)}=${queryValue(value)}`).join("&")}`;
}

function stripeReturnUrls(flow, options = {}) {
  const base = stripeReturnBase(flow, options.returnOwner);
  switch (flow) {
    case RETURN_FLOWS.BUSINESS_INVOICE:
      return {
        successUrl: withQuery(base, [
          ["paymentStatus", "payment-success"],
          ["invoiceId", options.invoiceId],
          ["businessId", options.businessId],
          ["paymentId", options.paymentId],
          ["checkoutSessionId", CHECKOUT_SESSION_ID],
        ]),
        cancelUrl: withQuery(base, [
          ["paymentStatus", "payment-cancelled"],
          ["invoiceId", options.invoiceId],
          ["businessId", options.businessId],
          ["paymentId", options.paymentId],
        ]),
      };
    case RETURN_FLOWS.BUSINESS_ROTH:
      return {
        successUrl: withQuery(base, [
          ["roth_purchase", "success"],
          ["purchaseId", options.purchaseId],
          ["session_id", CHECKOUT_SESSION_ID],
        ]),
        cancelUrl: withQuery(base, [
          ["roth_purchase", "cancelled"],
          ["purchaseId", options.purchaseId],
        ]),
      };
    case RETURN_FLOWS.GIFT:
      return {
        successUrl: withQuery(base, [
          ["gift_payment", "success"],
          ["giftDraftId", options.giftDraftId],
          ["session_id", CHECKOUT_SESSION_ID],
        ]),
        cancelUrl: withQuery(base, [
          ["gift_payment", "cancelled"],
          ["giftDraftId", options.giftDraftId],
        ]),
      };
    case RETURN_FLOWS.HEALTH_PLUS:
      return {
        successUrl: withQuery(base, [
          ["health", "success"],
          ["bookingId", options.bookingId],
        ]),
        cancelUrl: withQuery(base, [
          ["health", "cancelled"],
          ["bookingId", options.bookingId],
        ]),
      };
    case RETURN_FLOWS.SENDER_DELIVERY:
      return {
        successUrl: withQuery(base, [
          ["sender_payment", "success"],
          ["paymentSessionId", options.paymentSessionId],
          ["checkoutSessionId", CHECKOUT_SESSION_ID],
        ]),
        cancelUrl: withQuery(base, [
          ["sender_payment", "cancelled"],
          ["paymentSessionId", options.paymentSessionId],
        ]),
      };
    case RETURN_FLOWS.WALLET_TOP_UP:
      return {
        successUrl: withQuery(base, [
          ["wallet_topup", "success"],
          ["session_id", CHECKOUT_SESSION_ID],
        ]),
        cancelUrl: withQuery(base, [["wallet_topup", "cancelled"]]),
      };
    default:
      throw new Error(`Unsupported Stripe return flow: ${flow}`);
  }
}

module.exports = {
  CHECKOUT_SESSION_ID,
  FIXED_RETURN_BASES,
  RETURN_FLOWS,
  RETURN_OWNERS,
  resolveReturnOwner,
  stripeReturnBase,
  stripeReturnUrls,
};
