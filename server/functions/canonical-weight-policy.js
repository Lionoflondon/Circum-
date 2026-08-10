/* eslint-disable require-jsdoc */
"use strict";

const WEIGHT_POLICY_VERSION = "circum-weight-bands-v1";

const WEIGHT_BANDS = Object.freeze([
  Object.freeze({id: "small_parcel", label: "Small Parcel", minKg: 0, maxKg: 5, surchargeGbp: 0, baseGbp: 0}),
  Object.freeze({id: "medium_parcel", label: "Medium Parcel", minKg: 5, maxKg: 10, surchargeGbp: 3, baseGbp: 3}),
  Object.freeze({id: "heavy_parcel", label: "Heavy Parcel", minKg: 10, maxKg: 20, surchargeGbp: 7, baseGbp: 7}),
  Object.freeze({id: "large_item", label: "Large Item", minKg: 20, maxKg: 40, surchargeGbp: 15, baseGbp: 15}),
  Object.freeze({id: "extra_heavy", label: "Extra Heavy", minKg: 40, maxKg: null, surchargeGbp: 25, baseGbp: 25}),
]);

function weightBandFor(weightKg) {
  const weight = Math.max(0, Number(weightKg) || 0);
  return WEIGHT_BANDS.find((band) => {
    const aboveMinimum = band.minKg === 0 ? weight >= 0 : weight > band.minKg;
    return aboveMinimum && (band.maxKg == null || weight <= band.maxKg);
  }) || WEIGHT_BANDS[WEIGHT_BANDS.length - 1];
}

function weightSurcharge(weightKg) {
  return weightBandFor(weightKg).surchargeGbp;
}

function repriceWeightFromQuote(quote = {}, weightKg) {
  const originalWeightKg = Number(quote.weightKg || 0);
  const originalWeightCharge = Number.isFinite(Number(quote.weightSurcharge)) ?
    Number(quote.weightSurcharge) : weightSurcharge(originalWeightKg);
  const revisedWeightCharge = weightSurcharge(weightKg);
  const weightDelta = revisedWeightCharge - originalWeightCharge;
  const originalTotal = Number(quote.total || quote.finalAmount || quote.amountDue || 0);
  const revisedTotal = Math.round(Math.max(0, originalTotal + weightDelta) * 100) / 100;
  const riderBaseShare = Number(quote.riderBaseShare || 0);
  const platformBaseShare = Number(quote.circumBaseShare || quote.platformBaseShare || 0);
  const shareTotal = riderBaseShare + platformBaseShare;
  const riderRatio = shareTotal > 0 ? riderBaseShare / shareTotal : 0;
  const revisedRiderBaseShare = Math.round(Math.max(0, riderBaseShare + weightDelta * riderRatio) * 100) / 100;
  const revisedPlatformBaseShare = Math.round(Math.max(0, platformBaseShare + weightDelta * (1 - riderRatio)) * 100) / 100;
  const originalRiderPayout = Number(quote.riderPayout || quote.driverPayout || quote.riderEarning || 0);
  const revisedRiderPayout = Math.round(Math.max(0, originalRiderPayout + weightDelta * riderRatio) * 100) / 100;
  const originalPlatformRevenue = Number(quote.totalCircumRevenue || quote.platformRevenue || 0);
  const revisedPlatformRevenue = Math.round(Math.max(0, originalPlatformRevenue + weightDelta * (1 - riderRatio)) * 100) / 100;
  const lineItems = Array.isArray(quote.lineItems) ? quote.lineItems.map((item) =>
    item && item.key === "weight" ? {...item, amount: revisedWeightCharge} : item,
  ) : [];
  return {
    ...quote,
    weightKg: Number(weightKg),
    weightBand: weightBandFor(weightKg),
    weightPolicyVersion: WEIGHT_POLICY_VERSION,
    weightSurcharge: revisedWeightCharge,
    riderBaseShare: revisedRiderBaseShare,
    circumBaseShare: revisedPlatformBaseShare,
    platformBaseShare: revisedPlatformBaseShare,
    riderPayout: revisedRiderPayout,
    driverPayout: revisedRiderPayout,
    riderEarning: revisedRiderPayout,
    totalCircumRevenue: revisedPlatformRevenue,
    platformRevenue: revisedPlatformRevenue,
    lineItems,
    total: revisedTotal,
    finalAmount: revisedTotal,
    amountDue: revisedTotal,
  };
}

module.exports = {
  WEIGHT_BANDS,
  WEIGHT_POLICY_VERSION,
  repriceWeightFromQuote,
  weightBandFor,
  weightSurcharge,
};
