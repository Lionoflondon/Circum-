/* eslint-disable require-jsdoc */
const {weightBandFor: canonicalWeightBandFor} = require("./canonical-weight-policy");
const HEALTH_PLUS_MINIMUM_PENCE = 1100;
const HEALTH_PLUS_SERVICE_FEE_PENCE = 120;
const HEALTH_PLUS_BASIC_MONTHLY_PENCE = 1100;
const HEALTH_PLUS_PRIORITY_MONTHLY_PENCE = 2500;
const HEALTH_PLUS_FAMILY_MONTHLY_PENCE = 4000;
const DELIVERY_BASE_FARE_PENCE = 500;
const ADDITIONAL_FARE_PER_MILE_PENCE = 150;
const SHORT_TRIP_FARE_FLOOR_MILES = 1.6;
const MAX_VALIDATED_MEDICATION_WEIGHT_KG = 1000;

const PICKUP_STATUSES = [
  "scheduled",
  "assigned",
  "awaiting_pharmacy_collection",
  "collected",
  "out_for_delivery",
  "delivered",
  "failed",
  "cancelled",
];

function positiveNumber(value) {
  const number = Number(value);
  return Number.isFinite(number) && number >= 0 ? number : null;
}

function validateMedicationWeightKg(value) {
  const weight = Number(value);
  if (!Number.isFinite(weight) || weight <= 0 || weight > MAX_VALIDATED_MEDICATION_WEIGHT_KG) {
    const error = new Error("Health+ route distance and medication weight are required; weight must be a finite positive value within supported limits.");
    error.code = "invalid-medication-weight";
    throw error;
  }
  return weight;
}

function normalizePlan(plan) {
  const value = `${plan || "basic"}`.trim().toLowerCase();
  return ["basic", "priority", "family"].includes(value) ? value : "basic";
}

function healthPlusPlanContract(plan) {
  const normalized = normalizePlan(plan);
  if (normalized === "priority") {
    return {
      planType: "priority",
      subscriptionPlan: "priority",
      planLabel: "Health+ Priority",
      monthlyPricePence: HEALTH_PLUS_PRIORITY_MONTHLY_PENCE,
      monthlyPrice: HEALTH_PLUS_PRIORITY_MONTHLY_PENCE / 100,
      includedDeliveries: 4,
      includedPickups: 4,
      unlimitedDeliveries: false,
      unlimitedPickups: false,
      fairUseMonitored: false,
    };
  }
  if (normalized === "family") {
    return {
      planType: "family",
      subscriptionPlan: "family",
      planLabel: "Health+ Family",
      monthlyPricePence: HEALTH_PLUS_FAMILY_MONTHLY_PENCE,
      monthlyPrice: HEALTH_PLUS_FAMILY_MONTHLY_PENCE / 100,
      includedDeliveries: null,
      includedPickups: null,
      unlimitedDeliveries: true,
      unlimitedPickups: true,
      fairUseMonitored: true,
    };
  }
  return {
    planType: "basic",
    subscriptionPlan: "basic",
    planLabel: "Health+ Basic",
    monthlyPricePence: HEALTH_PLUS_BASIC_MONTHLY_PENCE,
    monthlyPrice: HEALTH_PLUS_BASIC_MONTHLY_PENCE / 100,
    includedDeliveries: 2,
    includedPickups: 2,
    unlimitedDeliveries: false,
    unlimitedPickups: false,
    fairUseMonitored: false,
  };
}

function buildHealthPlusPlanFields(plan, current = {}) {
  const contract = healthPlusPlanContract(plan);
  const used = Math.max(0, Number(
      current.usedDeliveriesThisCycle ||
      current.usedPickupsThisCycle ||
      0,
  ));
  const remaining = contract.includedDeliveries == null ?
    null :
    Math.max(0, contract.includedDeliveries - used);
  return {
    ...contract,
    usedDeliveriesThisCycle: used,
    usedPickupsThisCycle: used,
    remainingDeliveriesThisCycle: remaining,
    remainingPickupsThisCycle: remaining,
    allowanceResetsMonthly: true,
    unusedPickupsRollOver: false,
    overagePolicy: "standard_health_plus_one_off_pricing",
  };
}

function buildCustodyEvent({
  eventType,
  actorType = "system",
  actorId = null,
  actorName = null,
  publicMessage = "",
  internalNote = null,
  statusAfterEvent = null,
  evidenceUrl = null,
} = {}) {
  return {
    eventType: `${eventType || "health_plus_custody_event"}`.trim(),
    timestamp: Date.now(),
    actorType: `${actorType || "system"}`.trim(),
    actorId,
    actorName,
    publicMessage: `${publicMessage || ""}`.trim(),
    internalNote,
    statusAfterEvent,
    evidenceUrl,
  };
}

function weightBandFor(weightKg) {
  const band = canonicalWeightBandFor(weightKg);
  return {category: band.label, minKg: band.minKg, maxKg: band.maxKg, surchargePence: band.surchargeGbp * 100};
}

function calculateDistanceFarePence(distanceMiles) {
  const distance = positiveNumber(distanceMiles);
  if (distance == null) return null;
  if (distance < SHORT_TRIP_FARE_FLOOR_MILES) return 0;
  return Math.round(distance * ADDITIONAL_FARE_PER_MILE_PENCE);
}

function calculateHealthPlusAmountPence(input = {}) {
  return calculateAuthoritativeHealthPlusPricing(input).amountPence;
}

function calculateAuthoritativeHealthPlusPricing(input = {}) {
  const routeFacts = input.routeFacts && typeof input.routeFacts === "object" ? input.routeFacts : null;
  const distanceMiles = positiveNumber(routeFacts && routeFacts.distanceMiles || input.distanceMiles);
  const medicationWeightKg = validateMedicationWeightKg(input.medicationWeightKg);
  if (distanceMiles == null) {
    const error = new Error(
        "Health+ route distance and medication weight are required " +
        "for pricing.",
    );
    error.code = "missing-pricing-inputs";
    throw error;
  }
  const frequency = normalizeSchedule(input.frequency);
  const recurring = input.recurring === true || frequency !== "one_off";
  const plan = normalizePlan(input.subscriptionPlan || input.healthPlusPlan);
  const planContract = healthPlusPlanContract(plan);
  const weightBand = weightBandFor(medicationWeightKg);
  const baseFarePence = DELIVERY_BASE_FARE_PENCE;
  const distanceFarePence = calculateDistanceFarePence(distanceMiles);
  const weightSurchargePence = weightBand.surchargePence;
  const serviceFeePence = HEALTH_PLUS_SERVICE_FEE_PENCE;
  const priorityFeePence = 0;
  const familySupportFeePence = 0;
  const recurringDiscountPence = 0;
  const roadChargePence = Math.max(0, Math.round(Number(input.roadChargeCustomerAmount || 0) * 100));
  const subtotalPence = baseFarePence + distanceFarePence +
    weightSurchargePence + serviceFeePence + roadChargePence;
  const oneOffAmountPence = Math.max(
      subtotalPence,
      HEALTH_PLUS_MINIMUM_PENCE,
  );
  const amountPence = recurring ?
    planContract.monthlyPricePence :
    oneOffAmountPence;
  return {
    amountPence,
    currency: "GBP",
    minimumApplied: !recurring && amountPence > subtotalPence,
    minimumAdjustmentPence: recurring ? 0 : amountPence - subtotalPence,
    baseFarePence,
    distanceFarePence,
    weightSurchargePence,
    serviceFeePence,
    roadChargePence,
    roadCharges: input.roadCharges || null,
    routeFacts,
    priorityFeePence,
    familySupportFeePence,
    recurringDiscountPence,
    subtotalPence,
    distanceMiles,
    medicationWeightKg,
    weightCategory: weightBand.category,
    frequency,
    recurring,
    subscriptionPlan: plan,
    planType: plan,
    monthlyPlanPricePence: planContract.monthlyPricePence,
    monthlyPlanPrice: planContract.monthlyPrice,
    includedPickups: planContract.includedPickups,
    includedDeliveries: planContract.includedDeliveries,
    unlimitedPickups: planContract.unlimitedPickups,
    fairUseMonitored: planContract.fairUseMonitored,
    overagePolicy: "standard_health_plus_one_off_pricing",
    source: "backend_authoritative_health_plus_v1",
  };
}

function moneyField(data, keys) {
  for (const key of keys) {
    const value = positiveNumber(data && data[key]);
    if (value != null) return value;
  }
  return null;
}

function nested(data, path) {
  return path.reduce((value, key) => value && value[key], data);
}

function firstPresent(values) {
  for (const value of values) {
    if (value != null) return value;
  }
  return null;
}

function healthPlusPricingInputFromBooking(booking = {}, profile = {}) {
  const pricingInputs = booking.pricingInputs || booking.pricingInput || {};
  const route = booking.route || booking.routeSummary || {};
  const medication = booking.medication || booking.parcel ||
    booking.package || {};
  const distanceMiles = firstPresent([
    moneyField(pricingInputs, ["distanceMiles"]),
    moneyField(route, ["distanceMiles", "miles"]),
    positiveNumber(nested(booking, ["route", "distance", "miles"])),
  ]);
  const medicationWeightKg = firstPresent([
    moneyField(pricingInputs, ["medicationWeightKg", "weightKg"]),
    moneyField(medication, ["medicationWeightKg", "weightKg"]),
    moneyField(booking, ["medicationWeightKg", "weightKg", "declaredWeightKg"]),
  ]);
  return {
    distanceMiles,
    medicationWeightKg,
    frequency: booking.frequency || profile.frequency,
    subscriptionPlan: booking.subscriptionPlan || booking.healthPlusPlan ||
      profile.subscriptionPlan || profile.healthPlusPlan,
    ...(booking.authoritativeRouteFacts ? {routeFacts: booking.authoritativeRouteFacts} : {}),
    ...(booking.roadCharges ? {roadCharges: booking.roadCharges} : {}),
    ...(booking.roadChargeCustomerAmount ? {roadChargeCustomerAmount: booking.roadChargeCustomerAmount} : {}),
  };
}

function normalizeSchedule(frequency) {
  const allowed = [
    "one_off",
    "weekly",
    "every_2_weeks",
    "every_28_days",
    "monthly",
    "custom",
  ];
  return allowed.includes(frequency) ? frequency : "one_off";
}

function buildHealthPlusCheckoutParams({
  bookingId,
  profileId,
  email,
  amountPence,
  recurring,
  successUrl,
  cancelUrl,
  metadata = {},
  discounts = null,
}) {
  const mode = recurring ? "subscription" : "payment";
  const lineItem = {
    quantity: 1,
    price_data: {
      currency: "gbp",
      product_data: {
        name: recurring ?
          "Circum Health+ recurring prescription pickup" :
          "Circum Health+ prescription pickup",
        description: "Medication pickup and sealed-package delivery service",
      },
      unit_amount: amountPence,
    },
  };

  if (recurring) {
    lineItem.price_data.recurring = {interval: "month"};
  }

  const params = {
    mode,
    payment_method_types: ["card"],
    customer_email: email || undefined,
    line_items: [lineItem],
    success_url: successUrl,
    cancel_url: cancelUrl,
    metadata: {
      feature: "health_plus",
      type: "health_plus_payment",
      bookingId,
      profileId,
      ...metadata,
    },
  };
  if (discounts) params.discounts = discounts;
  return params;
}

function buildAdminStatusUpdate(status, driverId) {
  if (!PICKUP_STATUSES.includes(status)) {
    throw new Error(`Unsupported Health+ pickup status: ${status}`);
  }

  const update = {
    status,
    updatedAt: Date.now(),
  };

  if (driverId) {
    update.assignedDriverId = driverId;
  }

  return update;
}

module.exports = {
  HEALTH_PLUS_MINIMUM_PENCE,
  HEALTH_PLUS_BASIC_MONTHLY_PENCE,
  HEALTH_PLUS_PRIORITY_MONTHLY_PENCE,
  HEALTH_PLUS_FAMILY_MONTHLY_PENCE,
  PICKUP_STATUSES,
  healthPlusPlanContract,
  buildHealthPlusPlanFields,
  buildCustodyEvent,
  calculateHealthPlusAmountPence,
  calculateAuthoritativeHealthPlusPricing,
  healthPlusPricingInputFromBooking,
  validateMedicationWeightKg,
  MAX_VALIDATED_MEDICATION_WEIGHT_KG,
  normalizeSchedule,
  buildHealthPlusCheckoutParams,
  buildAdminStatusUpdate,
};
