/* eslint-disable require-jsdoc */
"use strict";

function settlementProduct(delivery = {}) {
  const quote = delivery.pricingBreakdown && typeof delivery.pricingBreakdown === "object" ? delivery.pricingBreakdown : {};
  const service = `${delivery.serviceType || delivery.selectedServiceType || quote.serviceType || ""}`.trim().toLowerCase();
  const source = `${delivery.sourceModule || quote.sourceModule || ""}`.trim().toLowerCase();
  if (["health_plus", "healthplus"].includes(service) || source === "health_plus") return "health_plus";
  if (["gifts", "gift"].includes(service) || source === "gifts") return "gifts";
  if (delivery.businessMode === true || delivery.businessId || delivery.businessAccountId) return "business";
  if (service === "standard" || source === "sender" || source === "sender_mobile") return "standard";
  return "unknown";
}

function standardSettlementAllowed(delivery = {}) {
  return ["standard", "business"].includes(settlementProduct(delivery));
}

function canonicalRiderPayout(delivery = {}) {
  const candidates = [
    delivery.riderEarning,
    delivery.riderPayout,
    delivery.driverPayout,
    delivery.estimatedEarnings,
  ];
  for (const candidate of candidates) {
    const amount = Number(candidate);
    if (Number.isFinite(amount) && amount > 0) return amount;
  }
  return null;
}

function lifecycleSettlementAllowed(delivery = {}) {
  const product = settlementProduct(delivery);
  if (["standard", "business"].includes(product)) return true;
  if (!["gifts", "health_plus"].includes(product)) return false;
  return `${delivery.riderSettlementAuthority || ""}`.startsWith("canonical") &&
    canonicalRiderPayout(delivery) !== null;
}

module.exports = {
  canonicalRiderPayout,
  lifecycleSettlementAllowed,
  settlementProduct,
  standardSettlementAllowed,
};
