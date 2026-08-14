/* eslint-disable require-jsdoc */
"use strict";

const {quotePayload} = require("./sender-booking")._private;

function text(value) {
  return `${value || ""}`.trim();
}

function canonicalHealthPlusDeliveryPricing(input = {}) {
  const routeFacts = input.authoritativeRouteFacts || input.routeFacts;
  if (!routeFacts || routeFacts.authority !== "authoritative_route" ||
      !Number.isFinite(Number(routeFacts.distanceMiles))) {
    return null;
  }
  const quote = quotePayload({
    authoritativeRouteFacts: routeFacts,
    sourceModule: "health_plus",
    serviceType: "HEALTH_PLUS",
    weightKg: 0,
    parcel: {weightKg: 0},
    selectedVehicle: text(input.selectedVehicle || input.vehicleType || "motorbike"),
    selectedSpeed: text(input.selectedSpeed || "standard"),
    scheduledJourneyAt: input.scheduledAt || input.scheduledJourneyAt || null,
  }, text(input.healthPlusPickupId || input.bookingId || input.pickupId || "health_plus"));
  return {
    authority: "canonical_health_plus_delivery_pricing_v1",
    currency: "GBP",
    logisticsValue: quote.total,
    deliveryCharge: quote.total,
    riderEarning: quote.totalRiderEarnings,
    platformShare: quote.totalCircumRevenue,
    riderShareRate: quote.driverShare,
    platformShareRate: quote.platformShare,
    routeFacts: quote.routeFacts,
    selectedVehicle: quote.selectedVehicle,
    selectedSpeed: quote.selectedSpeed,
    weightContribution: 0,
    lineItems: quote.lineItems.map((item) => item.key === "weight" ? {...item, amount: 0} : item),
  };
}

module.exports = {canonicalHealthPlusDeliveryPricing};
