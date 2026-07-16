/* eslint-disable max-len */
"use strict";

const VANGUARD_PROTOCOL_VERSION = "vanguard_protocol_v1";

const VANGUARD_STATUSES = Object.freeze({
  notRequired: "not_required",
  optional: "optional",
  required: "required",
  pickupVerificationPending: "pickup_verification_pending",
  pickupVerified: "pickup_verified",
  secureCustody: "secure_custody",
  handoverPending: "handover_pending",
  handoverVerified: "handover_verified",
  completed: "completed",
  issueReported: "issue_reported",
});

const VANGUARD_TIMELINE = Object.freeze([
  "Vanguard pickup verification",
  "Secure custody",
  "Secure transit",
  "Secure handover",
]);

const VANGUARD_POLICY_KEYWORDS = Object.freeze([
  "passport",
  "passports",
  "controlled medicine",
  "controlled medicines",
  "controlled medication",
  "high-value electronics",
  "high value electronics",
  "luxury goods",
  "jewellery",
  "jewelry",
  "confidential legal document",
  "confidential legal documents",
  "legal document",
  "legal documents",
  "business critical",
  "business-critical",
  "secure document",
  "secure documents",
]);

function normalize(value) {
  return `${value || ""}`.toLowerCase().replace(/[^a-z0-9]+/g, " ").replace(/\s+/g, " ").trim();
}

function protocolEnabled(delivery = {}) {
  return delivery.vanguardProtocolEnabled === true ||
    delivery.vanguardEnabled === true ||
    delivery.isVanguard === true ||
    delivery.requiresVanguard === true ||
    (delivery.vanguardProtocol && delivery.vanguardProtocol.enabled === true) ||
    (delivery.vanguardProtection && delivery.vanguardProtection.enabled === true);
}

function irisRequiresVanguard(input = {}) {
  const text = normalize([
    input.itemName,
    input.description,
    input.packageType,
    input.category,
    input.repositoryMatch,
    input.reason,
  ].join(" "));
  return VANGUARD_POLICY_KEYWORDS.some((keyword) => text.includes(normalize(keyword)));
}

function requiredReason(input = {}) {
  if (input.irisRequiredReason) return input.irisRequiredReason;
  if (irisRequiresVanguard(input)) return "IRIS policy requires Vanguard for this delivery.";
  if (Number(input.declaredValueGbp || 0) > 250) return "Declared value requires Vanguard protocol.";
  return "";
}

function initialProtocolFields(input = {}) {
  const required = input.irisRequired === true ||
    input.required === true ||
    irisRequiresVanguard(input) ||
    Number(input.declaredValueGbp || 0) > 250;
  const enabled = input.manuallySelected === true || input.selected === true || required;
  if (!enabled) {
    return {
      vanguardProtocolEnabled: false,
      vanguardStatus: VANGUARD_STATUSES.notRequired,
    };
  }
  const status = VANGUARD_STATUSES.pickupVerificationPending;
  const reason = requiredReason(input);
  return {
    vanguardProtocolEnabled: true,
    vanguardRequiredReason: reason,
    vanguardStatus: status,
    vanguardVerificationState: {
      pickup: "pending",
      custody: "pending",
      handover: "pending",
    },
    vanguardAuditTrail: [{
      event: "vanguard_protocol_enabled",
      status,
      trigger: required ? "iris_policy_required" : "manual_user_selection",
      reason,
    }],
    vanguardEvidence: {
      pickup: [],
      handover: [],
    },
    vanguardProtocol: {
      enabled: true,
      required,
      version: VANGUARD_PROTOCOL_VERSION,
      status,
      reason,
      timeline: VANGUARD_TIMELINE,
    },
  };
}

function nextStatusForEvent(currentStatus, event) {
  const current = normalize(currentStatus).replace(/\s/g, "_");
  const normalizedEvent = normalize(event).replace(/\s/g, "_");
  if (normalizedEvent === "pickup_verified") return VANGUARD_STATUSES.secureCustody;
  if (normalizedEvent === "handover_pending") return VANGUARD_STATUSES.handoverPending;
  if (normalizedEvent === "handover_verified") return VANGUARD_STATUSES.completed;
  if (normalizedEvent === "issue_reported") return VANGUARD_STATUSES.issueReported;
  return current || VANGUARD_STATUSES.notRequired;
}

function canCompletePickup(delivery = {}) {
  if (!protocolEnabled(delivery)) return true;
  return [
    VANGUARD_STATUSES.pickupVerified,
    VANGUARD_STATUSES.secureCustody,
    VANGUARD_STATUSES.handoverPending,
    VANGUARD_STATUSES.handoverVerified,
    VANGUARD_STATUSES.completed,
  ].includes(delivery.vanguardStatus);
}

function canCompleteDropoff(delivery = {}) {
  if (!protocolEnabled(delivery)) return true;
  return [
    VANGUARD_STATUSES.handoverVerified,
    VANGUARD_STATUSES.completed,
  ].includes(delivery.vanguardStatus);
}

module.exports = {
  VANGUARD_PROTOCOL_VERSION,
  VANGUARD_STATUSES,
  VANGUARD_TIMELINE,
  canCompleteDropoff,
  canCompletePickup,
  initialProtocolFields,
  irisRequiresVanguard,
  nextStatusForEvent,
  protocolEnabled,
};
