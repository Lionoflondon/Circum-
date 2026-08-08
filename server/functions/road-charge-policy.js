"use strict";

const {ROAD_CHARGE_POLICY_VERSION, evaluateRoadCharges} = require("./road-charges-core");

function evaluateRoadChargePolicy({routeFacts, vehicle, product, vehicleProfile = {}, vehicleId = null, at, liabilityState = {}} = {}) {
  const result = evaluateRoadCharges({
    routeFacts,
    selectedVehicle: vehicle,
    vehicleProfile,
    vehicleId,
    at,
    liabilityState,
    pricingContext: "quote",
  });
  const lineItems = result.charges
      .filter((charge) => Number(charge.customerContributionPence || charge.amountPence || 0) > 0)
      .map((charge) => ({
        key: charge.type === "route_toll" ? "road_toll" : "daily_zone_charge",
        label: charge.chargeId === "congestion_charge" ? "Central London fee" : "Road charge",
        amount: Number(charge.customerContribution || charge.amount || 0),
        chargeType: charge.type,
        chargeId: charge.chargeId,
      }));
  return {
    version: ROAD_CHARGE_POLICY_VERSION,
    product: `${product || "standard"}`,
    vehicle: result.charges[0] && result.charges[0].vehicleClass || `${vehicle || "unknown"}`,
    routeFactsVersion: routeFacts && (routeFacts.geographyVersion || routeFacts.version) || null,
    centralLondonEntered: routeFacts && routeFacts.congestionZone && routeFacts.congestionZone.entered === true,
    approvedTariffApplied: result.authoritativePricingComplete === true && lineItems.length > 0,
    customerAmount: Number(result.customerContribution || 0),
    lineItems,
    breakdown: result,
    reason: result.reason || (lineItems.length > 0 ? "approved_tariff_applied" : "no_applicable_charge"),
  };
}

module.exports = {ROAD_CHARGE_POLICY_VERSION, evaluateRoadChargePolicy};
