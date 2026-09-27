"use strict";

const POLICY_VERSION = "rider-communications-v1";

const REQUIRED_EVENTS = Object.freeze({
  APPLICATION_DECISION: "rider_application_decision",
  DOCUMENT_ACTION: "rider_document_action_required",
  DELIVERY_EARNINGS: "rider_delivery_earnings",
  COMPENSATION: "rider_compensation",
  EARNINGS_ADJUSTMENT: "rider_earnings_adjustment",
  CONNECT_ACTION_REQUIRED: "rider_connect_action_required",
  CONNECT_ENABLED: "rider_connect_enabled",
  WITHDRAWAL_REQUESTED: "rider_withdrawal_requested",
  PAYOUT_PAID: "rider_payout_paid",
  PAYOUT_FAILED: "rider_payout_failed",
});

const PUSH_ONLY_EVENTS = Object.freeze([
  "rider_availability",
  "rider_delivery_offer",
  "rider_offer_expired",
  "rider_delivery_accepted",
  "rider_pickup_progress",
  "rider_in_transit",
  "rider_arrival",
  "rider_tip_received",
]);

function timestampMillis(value) {
  if (!value) return 0;
  if (typeof value === "number") return value;
  if (value instanceof Date) return value.getTime();
  if (typeof value.toMillis === "function") return value.toMillis();
  if (value.seconds != null || value._seconds != null) {
    return Number(value.seconds ?? value._seconds) * 1000 + Math.floor(Number(value.nanos ?? value._nanoseconds ?? 0) / 1e6);
  }
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function policyConfig({effectiveAt} = {}) {
  const millis = timestampMillis(effectiveAt);
  if (!millis) throw new Error("Rider email policy effectiveAt is required.");
  return {version: POLICY_VERSION, effectiveAt: new Date(millis).toISOString()};
}

function isForwardEligible(value, effectiveAt) {
  const eventAt = timestampMillis(value);
  return Boolean(eventAt && eventAt >= timestampMillis(effectiveAt));
}

module.exports = {
  POLICY_VERSION,
  REQUIRED_EVENTS,
  PUSH_ONLY_EVENTS,
  timestampMillis,
  policyConfig,
  isForwardEligible,
};
