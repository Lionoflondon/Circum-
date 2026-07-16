/* eslint-disable max-len, require-jsdoc */
const HOUR_MS = 60 * 60 * 1000;

const TERMINAL = new Set([
  "completed", "complete", "delivered", "cancelled", "canceled",
  "cancelled_by_sender", "cancelled_admin", "admin_removed_stale",
  "archived", "archived_stale", "archived_expired", "expired", "voided",
]);
const PICKED_UP = new Set([
  "collected", "picked_up", "pickup_verified", "in_transit",
  "navigating_to_dropoff", "arrived_at_dropoff", "pin_required",
]);
const ACTIVE = new Set([
  "accepted", "assigned", "rider_assigned", "navigating_to_pickup",
  "en_route_to_pickup", "arrived_at_pickup", "rider_arrived_pickup",
  "waiting", "pickup_verification", "issue_reported",
]);
const UNACCEPTED = new Set([
  "requested", "pending", "finding_rider", "broadcasting", "available",
]);
const RECOVERABLE = new Set([
  "recoverable_incomplete", "stale_blocked", "admin_review_required",
]);

function normalize(value) {
  return `${value || ""}`.trim().toLowerCase().replaceAll("-", "_");
}

function millis(value) {
  if (!value) return 0;
  if (typeof value === "number") return value;
  if (value instanceof Date) return value.getTime();
  if (typeof value.toMillis === "function") return value.toMillis();
  if (typeof value.seconds === "number") return value.seconds * 1000;
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function statusOf(delivery = {}) {
  return normalize(delivery.status || delivery.deliveryStatus || delivery.flowStatus);
}

function scheduledAt(delivery = {}) {
  const deliveryTime = delivery.deliveryTime && typeof delivery.deliveryTime === "object" ? delivery.deliveryTime : {};
  return millis(
      delivery.scheduledAt || delivery.scheduledFor || delivery.scheduledDateTime ||
      delivery.scheduledDate || deliveryTime.scheduledAt || deliveryTime.scheduledDate,
  );
}

function lastMeaningfulUpdate(delivery = {}) {
  return Math.max(
      millis(delivery.lastLifecycleAt),
      millis(delivery.lastStatusAt),
      millis(delivery.updatedAt),
      millis(delivery.acceptedAt),
      millis(delivery.assignedAt),
      millis(delivery.lastTrackingAt || delivery._lastTrackingAt),
      millis(delivery.createdAt),
      millis(delivery.requestedAt),
  );
}

function hasPickupEvidence(delivery = {}) {
  return Boolean(
      delivery.collectedAt || delivery.pickedUpAt || delivery.pickupVerifiedAt ||
      delivery.collectionConfirmedAt || delivery.collectionPinVerified === true ||
      delivery.pickupPinVerified === true,
  );
}

function hasOperationalHold(delivery = {}) {
  return delivery.disputeOpen === true || delivery.underReview === true ||
    delivery.supportHold === true || delivery.paymentInvestigation === true;
}

function hasWaitingState(delivery = {}) {
  const waiting = normalize(delivery.waitingState || delivery.waitingStatus);
  return Boolean(delivery.waitingStartedAt || delivery.noShowEligibleAt || delivery.noShowAt) ||
    ["waiting", "active", "no_show_review"].includes(waiting);
}

function evaluateDeliveryLock(delivery, {now = Date.now(), exists = true} = {}) {
  if (!exists || !delivery) {
    return {block: false, repair: true, archive: false, reason: "delivery_missing"};
  }
  const status = statusOf(delivery);
  if (TERMINAL.has(status) || delivery.active === false || delivery.archived === true) {
    return {block: false, repair: true, archive: false, reason: `terminal_${status || "record"}`};
  }
  if (PICKED_UP.has(status) || hasPickupEvidence(delivery)) {
    return {block: true, repair: false, archive: false, reason: "parcel_collected"};
  }
  if (hasOperationalHold(delivery)) {
    return {block: true, repair: false, archive: false, reason: "operational_hold"};
  }
  if (hasWaitingState(delivery) || status === "waiting") {
    return {block: true, repair: false, archive: false, reason: "collection_waiting_active"};
  }
  const schedule = scheduledAt(delivery);
  if (schedule && now < schedule + 2 * HOUR_MS) {
    return {block: true, repair: false, archive: false, reason: "scheduled_window_active"};
  }
  const age = now - lastMeaningfulUpdate(delivery);
  if (RECOVERABLE.has(status) && age >= 2 * HOUR_MS) {
    return {block: false, repair: true, archive: true, reason: "stale_recoverable_delivery"};
  }
  if (UNACCEPTED.has(status) && age >= 2 * HOUR_MS) {
    return {block: false, repair: true, archive: true, reason: "stale_unaccepted_delivery"};
  }
  if (ACTIVE.has(status)) {
    if (age >= 12 * HOUR_MS) {
      return {block: true, repair: false, archive: false, review: true, reason: `stale_${status}_requires_review`};
    }
    return {block: true, repair: false, archive: false, reason: `active_${status}`};
  }
  return {block: true, repair: false, archive: false, reason: `unresolved_${status || "unknown"}`};
}

module.exports = {
  ACTIVE,
  PICKED_UP,
  RECOVERABLE,
  TERMINAL,
  UNACCEPTED,
  evaluateDeliveryLock,
  hasPickupEvidence,
  lastMeaningfulUpdate,
  normalize,
  statusOf,
};
