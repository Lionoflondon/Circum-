/* eslint-disable require-jsdoc */
const HEALTH_PLUS_MINIMUM_PENCE = 1100;
const HEALTH_PLUS_SERVICE_FEE_PENCE = 120;
const HEALTH_PLUS_PRIORITY_FEE_PENCE = 299;
const HEALTH_PLUS_FAMILY_SUPPORT_FEE_PENCE = 399;
const HEALTH_PLUS_RECURRING_DISCOUNT_PENCE = 150;
const DELIVERY_BASE_FARE_PENCE = 500;
const ADDITIONAL_FARE_PER_MILE_PENCE = 150;
const SHORT_TRIP_FARE_FLOOR_MILES = 1.6;

const WEIGHT_BANDS = [
  {category: "Small Parcel", minKg: 0, maxKg: 5, surchargePence: 0},
  {category: "Medium Parcel", minKg: 5, maxKg: 10, surchargePence: 300},
  {category: "Heavy Parcel", minKg: 10, maxKg: 20, surchargePence: 700},
  {category: "Large Item", minKg: 20, maxKg: 40, surchargePence: 1500},
  {category: "Extra Heavy", minKg: 40, maxKg: null, surchargePence: 2500},
];

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

function normalizePlan(plan) {
  const value = `${plan || "basic"}`.trim().toLowerCase();
  return value || "basic";
}

function weightBandFor(weightKg) {
  const weight = Math.max(0, Number(weightKg || 0));
  return WEIGHT_BANDS.find((band) => {
    const aboveMinimum = weight > band.minKg || band.minKg === 0 && weight >= 0;
    const belowMaximum = band.maxKg == null || weight <= band.maxKg;
    return aboveMinimum && belowMaximum;
  }) || WEIGHT_BANDS[0];
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
  const distanceMiles = positiveNumber(input.distanceMiles);
  const medicationWeightKg = positiveNumber(input.medicationWeightKg);
  if (distanceMiles == null || medicationWeightKg == null) {
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
  const weightBand = weightBandFor(medicationWeightKg);
  const baseFarePence = DELIVERY_BASE_FARE_PENCE;
  const distanceFarePence = calculateDistanceFarePence(distanceMiles);
  const weightSurchargePence = weightBand.surchargePence;
  const serviceFeePence = HEALTH_PLUS_SERVICE_FEE_PENCE;
  const priorityFeePence = plan === "priority" ?
    HEALTH_PLUS_PRIORITY_FEE_PENCE :
    0;
  const familySupportFeePence = plan === "family" ?
    HEALTH_PLUS_FAMILY_SUPPORT_FEE_PENCE :
    0;
  const recurringDiscountPence = recurring ?
    HEALTH_PLUS_RECURRING_DISCOUNT_PENCE :
    0;
  const subtotalPence = baseFarePence + distanceFarePence +
    weightSurchargePence + serviceFeePence + priorityFeePence +
    familySupportFeePence - recurringDiscountPence;
  const amountPence = Math.max(subtotalPence, HEALTH_PLUS_MINIMUM_PENCE);
  return {
    amountPence,
    currency: "GBP",
    minimumApplied: amountPence > subtotalPence,
    minimumAdjustmentPence: amountPence - subtotalPence,
    baseFarePence,
    distanceFarePence,
    weightSurchargePence,
    serviceFeePence,
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

  return {
    mode,
    payment_method_types: ["card"],
    customer_email: email || undefined,
    line_items: [lineItem],
    success_url: successUrl,
    cancel_url: cancelUrl,
    metadata: {
      feature: "health_plus",
      bookingId,
      profileId,
    },
  };
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
  HEALTH_PLUS_PRIORITY_FEE_PENCE,
  HEALTH_PLUS_FAMILY_SUPPORT_FEE_PENCE,
  HEALTH_PLUS_RECURRING_DISCOUNT_PENCE,
  PICKUP_STATUSES,
  calculateHealthPlusAmountPence,
  calculateAuthoritativeHealthPlusPricing,
  healthPlusPricingInputFromBooking,
  normalizeSchedule,
  buildHealthPlusCheckoutParams,
  buildAdminStatusUpdate,
};
