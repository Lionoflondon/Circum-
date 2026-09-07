"use strict";

const lifecycle = require("./delivery-lifecycle-core");

function pickupVerificationRequired(delivery = {}) {
  const irisVerification = (delivery.iris && delivery.iris.verification) || {};
  return (
    delivery.vanguardProtocolEnabled === true ||
    delivery.vanguardEnabled === true ||
    delivery.requiresVanguard === true ||
    delivery.verificationRequired === true ||
    delivery.requiresVerification === true ||
    delivery.pickupPinRequired === true ||
    delivery.senderPinRequired === true ||
    delivery.pickupEvidenceRequired === true ||
    delivery.isHealthPlus === true ||
    delivery.isGift === true ||
    irisVerification.senderPinRequired === true ||
    irisVerification.pickupEvidenceRequired === true
  );
}

function canTransitionDeliveryStatusForPolicy(delivery, from, to) {
  const current = lifecycle.normalizeStatus(from);
  const next = lifecycle.normalizeStatus(to);
  if (!lifecycle.canTransitionDeliveryStatus(current, next)) return false;
  if (["arrived_at_pickup", "waiting"].includes(current) && next === "collected") {
    return !pickupVerificationRequired(delivery);
  }
  return true;
}

module.exports = {
  ...lifecycle,
  canTransitionDeliveryStatusForPolicy,
  pickupVerificationRequired,
};
