/* eslint-disable require-jsdoc */
const HEALTH_PLUS_MINIMUM_PENCE = 1100;
const HEALTH_PLUS_SERVICE_FEE_PENCE = 120;
const DEFAULT_DISTANCE_FARE_PENCE = 380;
const BASE_FARE_PENCE = 600;

const PICKUP_STATUSES = [
  "scheduled",
  "assigned",
  "awaiting_pharmacy_collection",
  "collected",
  "out_for_delivery",
  "delivered",
  "failed",
  "cancelled",
  "prescription_not_ready",
  "customer_unavailable",
  "escalated",
  "rescheduled",
  "override_completed",
];

const HEALTH_PLUS_PLANS = Object.freeze({
  core: {monthlyPrice: 15, includedDeliveries: 2, overageRate: 7.5},
  priority: {monthlyPrice: 25, includedDeliveries: 4, overageRate: 6.25},
  family: {monthlyPrice: 40, includedDeliveries: null, overageRate: null},
  custom: {monthlyPrice: 60, includedDeliveries: 0, overageRate: null},
});

const HEALTH_PLUS_RISK_STATUSES = [
  "scheduled",
  "awaiting_collection",
  "prescription_not_ready",
  "customer_unavailable",
  "no_rider_assigned",
  "missed_medication_risk",
  "admin_review_required",
  "escalated",
  "completed",
];

function normalizeHealthPlusPlan(planType) {
  const normalized = `${planType || ""}`.trim().toLowerCase();
  return HEALTH_PLUS_PLANS[normalized] ? normalized : "core";
}

function buildHealthPlusPlanFields(planType, overrides = {}) {
  const normalized = normalizeHealthPlusPlan(planType);
  const defaults = HEALTH_PLUS_PLANS[normalized];
  const included = normalized === "custom" ?
    Math.max(0, Number(overrides.customIncludedDeliveries || 0)) :
    defaults.includedDeliveries;
  const used = Math.max(0, Number(overrides.usedDeliveriesThisCycle || 0));
  return {
    planType: normalized,
    monthlyPrice: normalized === "custom" ?
      Math.max(60, Number(overrides.monthlyPrice || 60)) :
      defaults.monthlyPrice,
    includedDeliveries: included,
    usedDeliveriesThisCycle: used,
    remainingDeliveriesThisCycle: included == null ?
      null : Math.max(0, included - used),
    subscriptionStatus: overrides.subscriptionStatus || "active",
    fairUseLimit: normalized === "family" ?
      Number(overrides.fairUseLimit || 0) || null : null,
    customIncludedDeliveries: normalized === "custom" ? included : null,
    customOverageRate: normalized === "custom" ?
      Number(overrides.customOverageRate || 0) || null : null,
    overageRate: defaults.overageRate,
    isVanguard: true,
    trustPoints: 6,
  };
}

function buildCustodyEvent({
  eventType,
  actorType = "system",
  actorId = null,
  actorName = null,
  publicMessage,
  internalNote = null,
  evidenceUrl = null,
  statusAfterEvent,
  timestamp = Date.now(),
}) {
  if (!eventType || !publicMessage || !statusAfterEvent) {
    throw new Error(
        "Health+ custody events require type, public message and status.",
    );
  }
  return {
    eventType,
    timestamp,
    actorType,
    actorId,
    actorName,
    publicMessage,
    internalNote,
    evidenceUrl,
    statusAfterEvent,
  };
}

function calculateHealthPlusAmountPence(input = {}) {
  const baseFare = input.baseFarePence == null ?
    BASE_FARE_PENCE :
    input.baseFarePence;
  const distanceFare = input.distanceFarePence == null ?
    DEFAULT_DISTANCE_FARE_PENCE :
    input.distanceFarePence;
  const weightSurcharge = input.weightSurchargePence == null ?
    0 :
    input.weightSurchargePence;
  const serviceFee = input.serviceFeePence == null ?
    HEALTH_PLUS_SERVICE_FEE_PENCE :
    input.serviceFeePence;
  const subtotal = baseFare + distanceFare + weightSurcharge + serviceFee;
  return Math.max(subtotal, HEALTH_PLUS_MINIMUM_PENCE);
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
  currency = "gbp",
  successUrl,
  cancelUrl,
}) {
  const mode = recurring ? "subscription" : "payment";
  const lineItem = {
    quantity: 1,
    price_data: {
      currency,
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
  PICKUP_STATUSES,
  calculateHealthPlusAmountPence,
  normalizeSchedule,
  buildHealthPlusCheckoutParams,
  buildAdminStatusUpdate,
  HEALTH_PLUS_PLANS,
  HEALTH_PLUS_RISK_STATUSES,
  normalizeHealthPlusPlan,
  buildHealthPlusPlanFields,
  buildCustodyEvent,
};
