/* eslint-disable require-jsdoc */
"use strict";

function settlementProduct(delivery = {}) {
  const quote =
    delivery.pricingBreakdown && typeof delivery.pricingBreakdown === "object" ?
      delivery.pricingBreakdown :
      {};
  const service =
    `${delivery.serviceType || delivery.selectedServiceType || quote.serviceType || ""}`
      .trim()
      .toLowerCase();
  const source = `${delivery.sourceModule || quote.sourceModule || ""}`
    .trim()
    .toLowerCase();
  if (
    ["health_plus", "healthplus"].includes(service) ||
    source === "health_plus"
  ) {
    return "health_plus";
  }
  if (["gifts", "gift"].includes(service) || source === "gifts") return "gifts";
  if (
    delivery.businessMode === true ||
    delivery.businessId ||
    delivery.businessAccountId
  ) {
    return "business";
  }
  if (
    service === "standard" ||
    source === "sender" ||
    source === "sender_mobile"
  ) {
    return "standard";
  }
  return "unknown";
}

function standardSettlementAllowed(delivery = {}) {
  return ["standard", "business"].includes(settlementProduct(delivery));
}

module.exports = {settlementProduct, standardSettlementAllowed};
