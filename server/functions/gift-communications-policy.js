/* eslint-disable require-jsdoc */
"use strict";

const POLICY_VERSION = "gifts-communications-v1";
const POLICY_METADATA_COLLECTION = "systemConfiguration";
const POLICY_METADATA_ID = "giftsCommunicationsPolicy";
const POLICY_EFFECTIVE_AT_ENV = "GIFTS_COMMUNICATION_POLICY_EFFECTIVE_AT";

const EVENT = Object.freeze({
  PAYMENT_CONFIRMED: "gift_payment_confirmed",
  PAYMENT_PROBLEM: "gift_payment_problem",
  APPROVED: "gift_approved",
  REJECTED: "gift_rejected",
  READY: "gift_ready_for_delivery",
  DELIVERED: "gift_delivered",
  STORY_READY: "gift_story_ready",
  SUBMITTED: "gift_submitted",
  CURATION_STARTED: "curation_started",
  DELIVERY_PROGRESS: "delivery_progress",
  REFUND: "gift_refund",
});

const COMMUNICATION_POLICY = Object.freeze({
  [EVENT.PAYMENT_CONFIRMED]: Object.freeze({classification: "sender_email", recipients: ["sender"], source: "giftRequests"}),
  [EVENT.PAYMENT_PROBLEM]: Object.freeze({classification: "sender_email", recipients: ["sender"], source: "giftPaymentDrafts|giftRequests"}),
  [EVENT.APPROVED]: Object.freeze({classification: "sender_email", recipients: ["sender"], source: "giftRequests"}),
  [EVENT.REJECTED]: Object.freeze({classification: "sender_email", recipients: ["sender"], source: "giftRequests"}),
  [EVENT.READY]: Object.freeze({classification: "sender_email", recipients: ["sender"], source: "giftRequests"}),
  [EVENT.DELIVERED]: Object.freeze({classification: "sender_email", recipients: ["sender"], source: "giftRequests"}),
  [EVENT.STORY_READY]: Object.freeze({classification: "sender_and_recipient_email", recipients: ["sender", "recipient"], source: "giftRequests"}),
  [EVENT.SUBMITTED]: Object.freeze({classification: "push_only", recipients: ["sender"], source: "giftRequests"}),
  [EVENT.CURATION_STARTED]: Object.freeze({classification: "push_only", recipients: ["sender"], source: "giftRequests"}),
  [EVENT.DELIVERY_PROGRESS]: Object.freeze({classification: "push_only", recipients: ["sender"], source: "deliveryRequests"}),
  [EVENT.REFUND]: Object.freeze({classification: "not_applicable", recipients: [], source: "none"}),
});

const PAYMENT_PROBLEM_STATES = new Set([
  "failed", "declined", "requires_payment_method", "requires_action", "requires_confirmation",
  "canceled", "cancelled", "payment_failed", "payment_declined", "payment_interrupted",
]);
const HARD_PAYMENT_FAILURE_STATES = new Set(["failed", "declined", "requires_payment_method", "canceled", "cancelled", "payment_failed", "payment_declined"]);
const PAID_STATES = new Set(["paid", "succeeded", "success", "roth_paid", "stripe_paid"]);

const text = (value) => `${value || ""}`.trim();

function lower(value) {
  return text(value).toLowerCase();
}

function timestampMillis(value) {
  if (!value) return 0;
  if (typeof value === "number") return value > 1e12 ? value : value * 1000;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (typeof value === "object" && (value.seconds != null || value._seconds != null)) {
    return Number(value.seconds ?? value._seconds) * 1000 + Math.floor(Number(value.nanos ?? value._nanoseconds ?? 0) / 1e6);
  }
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function timestampFieldForEvent(eventType) {
  return {
    [EVENT.PAYMENT_CONFIRMED]: "paidAt",
    [EVENT.PAYMENT_PROBLEM]: "paymentProblemAt",
    [EVENT.APPROVED]: "approvedAt",
    [EVENT.REJECTED]: "rejectedAt",
    [EVENT.READY]: "readyForDeliveryAt",
    [EVENT.DELIVERED]: "deliveredAt",
    [EVENT.STORY_READY]: "giftStoryAvailableAt",
  }[eventType] || "";
}

function authoritativeEventAt(data = {}, eventType) {
  const fields = {
    [EVENT.PAYMENT_CONFIRMED]: ["paidAt"],
    [EVENT.PAYMENT_PROBLEM]: ["paymentProblemAt", "paymentFailedAt"],
    [EVENT.APPROVED]: ["approvedAt"],
    [EVENT.REJECTED]: ["rejectedAt"],
    [EVENT.READY]: ["readyForDeliveryAt", "readyForGiftDeliveryAt"],
    [EVENT.DELIVERED]: ["deliveredAt", "giftStoryAvailableAt"],
    [EVENT.STORY_READY]: ["giftStoryAvailableAt"],
  }[eventType] || [];
  for (const field of fields) {
    const millis = timestampMillis(data[field]);
    if (millis) return {field, millis};
  }
  return {field: "", millis: 0};
}

function eventIsPostPolicy(data, eventType, policyEffectiveAt) {
  const effective = timestampMillis(policyEffectiveAt);
  const eventAt = authoritativeEventAt(data, eventType);
  return Boolean(effective && eventAt.millis >= effective);
}

function paymentProblemKind(data = {}) {
  const state = lower(data.paymentStatus || data.paymentState || data.status);
  if (!PAYMENT_PROBLEM_STATES.has(state)) return "unconfirmed";
  const received = Number(data.amountReceivedPence ?? data.amount_received ?? data.amountReceived ?? 0);
  const chargeSucceeded = data.chargeSucceeded === true || data.paymentSucceeded === true || received > 0;
  return chargeSucceeded || !HARD_PAYMENT_FAILURE_STATES.has(state) ? "unconfirmed" : "failed";
}

function isPaymentProblemState(data = {}) {
  const state = lower(data.paymentStatus || data.paymentState || data.status);
  return PAYMENT_PROBLEM_STATES.has(state) && !PAID_STATES.has(state);
}

function metadataPath() {
  return `${POLICY_METADATA_COLLECTION}/${POLICY_METADATA_ID}`;
}

function parseEffectiveAt(value) {
  const millis = timestampMillis(value);
  if (!millis) throw new Error("A valid Gifts communications policy effective time is required.");
  return new Date(millis).toISOString();
}

function policyConfig({effectiveAt, version = POLICY_VERSION} = {}) {
  return {version, effectiveAt: parseEffectiveAt(effectiveAt), policyPath: metadataPath()};
}

async function readPolicyConfig({db, env = process.env} = {}) {
  const snapshot = db && await db.collection(POLICY_METADATA_COLLECTION).doc(POLICY_METADATA_ID).get();
  if (snapshot && snapshot.exists) {
    const data = snapshot.data() || {};
    if (data.version !== POLICY_VERSION) throw new Error("Unsupported Gifts communications policy version.");
    return policyConfig(data);
  }
  const configured = text(env[POLICY_EFFECTIVE_AT_ENV]);
  if (!configured) throw new Error("Gifts communications policy cutover metadata is missing.");
  return policyConfig({effectiveAt: configured});
}

async function recordPolicyConfig({db, effectiveAt, version = POLICY_VERSION, actor = "deployment"} = {}) {
  const config = policyConfig({effectiveAt, version});
  const ref = db.collection(POLICY_METADATA_COLLECTION).doc(POLICY_METADATA_ID);
  const existing = await ref.get();
  if (existing.exists) {
    const current = existing.data() || {};
    if (current.version !== config.version || parseEffectiveAt(current.effectiveAt) !== config.effectiveAt) {
      throw new Error("Gifts communications policy cutover metadata already exists with different values.");
    }
    return {status: "duplicate", ...config};
  }
  await ref.create({...config, recordedBy: actor, recordedAt: new Date()});
  return {status: "recorded", ...config};
}

module.exports = {
  COMMUNICATION_POLICY,
  EVENT,
  PAYMENT_PROBLEM_STATES,
  POLICY_EFFECTIVE_AT_ENV,
  POLICY_METADATA_COLLECTION,
  POLICY_METADATA_ID,
  POLICY_VERSION,
  authoritativeEventAt,
  eventIsPostPolicy,
  isPaymentProblemState,
  paymentProblemKind,
  policyConfig,
  readPolicyConfig,
  recordPolicyConfig,
  timestampFieldForEvent,
  timestampMillis,
};
