"use strict";

const ROAD_CHARGE_POLICY_VERSION = "circum_road_charges_v1";

function money(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed >= 0 ? Math.round(parsed * 100) / 100 : 0;
}

function vehicleKey(value) {
  const normalized = `${value || ""}`.toLowerCase();
  if (normalized.includes("van")) return "van";
  if (normalized.includes("car")) return "car";
  return "motorbike";
}

function evaluateRoadChargePolicy({routeFacts, vehicle, product, approvedPolicy = {}} = {}) {
  const facts = routeFacts && typeof routeFacts === "object" ? routeFacts : null;
  const key = vehicleKey(vehicle);
  const centralLondon = facts && facts.centralLondonEntered === true;
  const centralPolicy = approvedPolicy.centralLondon && approvedPolicy.centralLondon[key];
  const centralAmount = centralLondon && centralPolicy && centralPolicy.approved === true ?
    money(centralPolicy.amount) : 0;
  const lineItems = centralAmount > 0 ? [{
    key: "central_london",
    label: "Central London fee",
    amount: centralAmount,
    chargeType: "daily_liability",
  }] : [];
  return {
    version: ROAD_CHARGE_POLICY_VERSION,
    product: `${product || "standard"}`,
    vehicle: key,
    routeFactsVersion: facts && facts.version || null,
    centralLondonEntered: centralLondon,
    approvedTariffApplied: lineItems.length > 0,
    customerAmount: money(lineItems.reduce((sum, item) => sum + item.amount, 0)),
    lineItems,
    reason: lineItems.length > 0 ? "approved_tariff_applied" :
      centralLondon ? "no_approved_tariff" : "route_outside_configured_geography",
  };
}

module.exports = {ROAD_CHARGE_POLICY_VERSION, evaluateRoadChargePolicy};
