"use strict";

const DELIVERY_DOMAIN_VERSION = 1;
const CORE_FIELDS = Object.freeze([
  "deliveryId",
  "status",
  "senderId",
  "recipientId",
  "riderId",
  "createdAt",
  "completedAt",
  "dispatchId",
  "trackingId",
  "pricingId",
  "paymentId",
  "evidenceId",
  "eventVersion",
]);

const CANONICAL_STATUSES = Object.freeze([
  "requested",
  "accepted",
  "navigating_to_pickup",
  "arrived_at_pickup",
  "pickup_verified",
  "collected",
  "navigating_to_dropoff",
  "arrived_at_dropoff",
  "delivered",
  "cancelled",
  "failed",
]);

function text(value) {
  return `${value || ""}`.trim();
}

function optionalId(value) {
  const id = text(value);
  return id || null;
}

function canonicalStatus(value) {
  const status = text(value)
    .toLowerCase()
    .replace(/[-\s]+/g, "_");
  if (!CANONICAL_STATUSES.includes(status)) {
    throw new TypeError(`Unsupported delivery status: ${status || "empty"}`);
  }
  return status;
}

function createDeliveryCore(input = {}) {
  const deliveryId = optionalId(input.deliveryId || input.id);
  if (!deliveryId) throw new TypeError("deliveryId is required");
  return Object.freeze({
    deliveryId,
    status: canonicalStatus(
      input.status || input.deliveryStatus || "requested",
    ),
    senderId: optionalId(input.senderId || input.userId || input.customerId),
    recipientId: optionalId(
      input.recipientId || input.receiverId || input.recipientUserId,
    ),
    riderId: optionalId(
      input.riderId || input.assignedRiderId || input.driverId,
    ),
    createdAt: input.createdAt || null,
    completedAt: input.completedAt || null,
    dispatchId: optionalId(input.dispatchId),
    trackingId: optionalId(input.trackingId),
    pricingId: optionalId(input.pricingId),
    paymentId: optionalId(input.paymentId),
    evidenceId: optionalId(input.evidenceId),
    eventVersion: Number(input.eventVersion || DELIVERY_DOMAIN_VERSION),
  });
}

function assertDeliveryCore(core) {
  const candidate = createDeliveryCore(core);
  for (const key of Object.keys(candidate)) {
    if (!CORE_FIELDS.includes(key)) {
      throw new TypeError(`Unknown core field: ${key}`);
    }
  }
  return candidate;
}

function extensionReference({context, id, version = 1} = {}) {
  const extensionId = optionalId(id);
  const name = text(context);
  if (!name || !extensionId) return null;
  return Object.freeze({
    context: name,
    id: extensionId,
    version: Number(version) || 1,
  });
}

module.exports = {
  CANONICAL_STATUSES,
  CORE_FIELDS,
  DELIVERY_DOMAIN_VERSION,
  assertDeliveryCore,
  createDeliveryCore,
  extensionReference,
};
