/* eslint-disable require-jsdoc */
"use strict";

const STRATEGIES = Object.freeze({
  OPEN_DISPATCH: "open_dispatch",
  SCHEDULED_DELIVERY: "scheduled_delivery",
  ADMIN_SCHEDULED_DELIVERY: "admin_scheduled_delivery",
});

const TERMINAL_STATUSES = new Set([
  "delivered", "completed", "cancelled", "canceled", "expired", "failed",
]);

function text(value) {
  return `${value || ""}`.trim();
}

function normalized(value) {
  return text(value).toLowerCase().replace(/[\s-]+/g, "_");
}

function millis(value) {
  if (!value) return 0;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value.seconds === "number") return value.seconds * 1000;
  const parsed = Date.parse(`${value}`);
  return Number.isFinite(parsed) ? parsed : 0;
}

function productType(delivery = {}) {
  const value = normalized(
      delivery.productType || delivery.sourceModule || delivery.serviceType ||
      delivery.category || delivery.deliveryType,
  );
  if (value.includes("gift")) return "gift";
  if (value.includes("health")) return "health_plus";
  return "standard";
}

function scheduledAtMillis(delivery = {}) {
  const deliveryTime = delivery.deliveryTime || {};
  return millis(
      delivery.scheduledAt || delivery.scheduledFor ||
      delivery.scheduledJourneyAt || delivery.scheduledPickupDate ||
      deliveryTime.scheduledJourneyAt || deliveryTime.scheduledAt,
  );
}

function hasScheduledIntent(delivery = {}) {
  const deliveryTime = delivery.deliveryTime || {};
  return normalized(delivery.fulfilmentMode || delivery.fulfillmentMode) === "scheduled" ||
    normalized(deliveryTime.type) === "scheduled" ||
    scheduledAtMillis(delivery) > 0;
}

function fulfilmentStrategy(delivery = {}) {
  const product = productType(delivery);
  if (product === "gift") return STRATEGIES.SCHEDULED_DELIVERY;
  if (product === "health_plus") {
    const deliveryTime = delivery.deliveryTime || {};
    const explicitSchedule = delivery.scheduledDelivery === true ||
      delivery.useScheduledDeliveryEngine === true ||
      normalized(delivery.fulfilmentMode || delivery.fulfillmentMode) === "scheduled" ||
      normalized(deliveryTime.type) === "scheduled";
    return explicitSchedule ? STRATEGIES.SCHEDULED_DELIVERY : STRATEGIES.OPEN_DISPATCH;
  }
  if (hasScheduledIntent(delivery)) return STRATEGIES.SCHEDULED_DELIVERY;
  return STRATEGIES.OPEN_DISPATCH;
}

function assignedRiderId(delivery = {}) {
  return text(
      delivery.assignedRiderId || delivery.riderId || delivery.driverId ||
      delivery.assignedDriverId,
  );
}

function activationState(delivery = {}, now = Date.now()) {
  const strategy = fulfilmentStrategy(delivery);
  const status = normalized(delivery.status || delivery.deliveryStatus);
  if (TERMINAL_STATUSES.has(status)) return "terminal";
  if (strategy === STRATEGIES.OPEN_DISPATCH) return "open";
  const scheduled = scheduledAtMillis(delivery);
  if (!scheduled) {
    return productType(delivery) === "gift" && delivery.readyForDispatch === true ?
      "ready_dispatch" : "invalid_schedule";
  }
  if (scheduled > now) return "scheduled";
  return assignedRiderId(delivery) ? "ready_assigned" : "ready_dispatch";
}

function canStartScheduledDelivery(delivery = {}, riderId, now = Date.now()) {
  if (assignedRiderId(delivery) !== text(riderId)) return false;
  return activationState(delivery, now) === "ready_assigned";
}

function isOpenDispatchOffer(delivery = {}, now = Date.now()) {
  const state = activationState(delivery, now);
  return state === "open" || state === "ready_dispatch";
}

function activationPlan(delivery = {}, now = Date.now()) {
  const state = activationState(delivery, now);
  if (state === "ready_dispatch") {
    return {activate: true, mode: "open_dispatch", riderBusy: false, status: "requested"};
  }
  if (state === "ready_assigned") {
    return {activate: true, mode: "assigned", riderBusy: true, status: "ready"};
  }
  return {activate: false, mode: null, riderBusy: false, status: normalized(delivery.status)};
}

function domainBadge(delivery = {}) {
  const product = productType(delivery);
  if (product === "gift") return "Gift";
  if (product === "health_plus") return "Health+";
  return "Standard";
}

function trustPointsForScheduledDelivery(delivery = {}) {
  return productType(delivery) === "health_plus" ? 6 : 5;
}

function scheduledJobProjection(id, delivery = {}) {
  return {
    deliveryId: text(delivery.deliveryId || delivery.requestId || id),
    requestId: text(delivery.requestId || delivery.deliveryId || id),
    assignedRiderId: assignedRiderId(delivery),
    productType: productType(delivery),
    domainBadge: domainBadge(delivery),
    fulfilmentStrategy: fulfilmentStrategy(delivery),
    scheduledAt: delivery.scheduledAt || delivery.scheduledFor ||
      delivery.scheduledJourneyAt || delivery.scheduledPickupDate ||
      delivery.deliveryTime && delivery.deliveryTime.scheduledJourneyAt || null,
    scheduledWindow: delivery.scheduledWindow || delivery.scheduledPickupWindow ||
      delivery.deliveryTime && delivery.deliveryTime.scheduledWindow || null,
    pickupAddress: text(delivery.pickupAddress),
    dropoffAddress: text(delivery.dropoffAddress),
    earnings: Number(delivery.riderEarning || delivery.riderPayout ||
      delivery.driverPayout || delivery.estimatedEarnings || 0),
    instructions: text(delivery.riderInstructions || delivery.instructions ||
      delivery.packageDescription),
    status: normalized(delivery.status || "scheduled"),
    serviceType: text(delivery.serviceType || domainBadge(delivery)),
    activationState: activationState(delivery),
  };
}

module.exports = {
  STRATEGIES,
  activationPlan,
  activationState,
  assignedRiderId,
  canStartScheduledDelivery,
  domainBadge,
  fulfilmentStrategy,
  hasScheduledIntent,
  isOpenDispatchOffer,
  millis,
  productType,
  scheduledAtMillis,
  scheduledJobProjection,
  trustPointsForScheduledDelivery,
};
