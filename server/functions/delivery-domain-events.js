"use strict";

const {assertDeliveryCore, DELIVERY_DOMAIN_VERSION} = require("./delivery-domain-core");

const PLATFORM_EVENT_VERSION = 1;
const DELIVERY_EVENT_TYPES = Object.freeze([
  "DeliveryCreated",
  "DeliveryPriced",
  "PaymentAuthorised",
  "DispatchStarted",
  "RiderAssigned",
  "ParcelCollected",
  "DeliveryCompleted",
  "DeliveryClosed",
]);

function buildDeliveryDomainEvent({eventType, eventId, delivery, occurredAt, extensions = {}} = {}) {
  if (!DELIVERY_EVENT_TYPES.includes(eventType)) {
    throw new TypeError(`Unsupported delivery event: ${eventType || "empty"}`);
  }
  const core = assertDeliveryCore(delivery);
  return Object.freeze({
    eventId: eventId || `${eventType.toLowerCase()}_${core.deliveryId}`,
    eventType,
    eventVersion: PLATFORM_EVENT_VERSION,
    deliveryDomainVersion: DELIVERY_DOMAIN_VERSION,
    deliveryId: core.deliveryId,
    occurredAt: occurredAt || new Date().toISOString(),
    core,
    extensions: Object.freeze({...extensions}),
  });
}

module.exports = {
  DELIVERY_EVENT_TYPES,
  PLATFORM_EVENT_VERSION,
  buildDeliveryDomainEvent,
};
