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
];

function calculateHealthPlusAmountPence(input = {}) {
  const baseFare = input.baseFarePence ?? BASE_FARE_PENCE;
  const distanceFare = input.distanceFarePence ?? DEFAULT_DISTANCE_FARE_PENCE;
  const weightSurcharge = input.weightSurchargePence ?? 0;
  const serviceFee = input.serviceFeePence ?? HEALTH_PLUS_SERVICE_FEE_PENCE;
  const subtotal = baseFare + distanceFare + weightSurcharge + serviceFee;
  return Math.max(subtotal, HEALTH_PLUS_MINIMUM_PENCE);
}

function normalizeSchedule(frequency) {
  const allowed = [
    "one_off",
    "weekly",
    "every_2_weeks",
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
  PICKUP_STATUSES,
  calculateHealthPlusAmountPence,
  normalizeSchedule,
  buildHealthPlusCheckoutParams,
  buildAdminStatusUpdate,
};
