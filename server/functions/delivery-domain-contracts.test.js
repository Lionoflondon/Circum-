"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const core = require("./delivery-domain-core");
const events = require("./delivery-domain-events");
const services = require("./delivery-service-contracts");
const adapter = require("./delivery-domain-adapter");

test("delivery core remains intentionally small and excludes product fields", () => {
  const delivery = core.createDeliveryCore({
    id: "delivery-1",
    status: "delivered",
    senderId: "sender-1",
    giftId: "gift-1",
    businessOrderId: "business-1",
  });
  assert.deepEqual(Object.keys(delivery).sort(), [...core.CORE_FIELDS].sort());
  assert.equal("giftId" in delivery, false);
  assert.equal("businessOrderId" in delivery, false);
});

test("domain events are versioned and carry extensions outside the core", () => {
  const event = events.buildDeliveryDomainEvent({
    eventType: "DeliveryCompleted",
    delivery: {id: "delivery-2", status: "delivered"},
    extensions: {gift: {id: "gift-2", version: 1}},
  });
  assert.equal(event.eventVersion, 1);
  assert.equal(event.deliveryDomainVersion, 1);
  assert.equal(event.core.deliveryId, "delivery-2");
  assert.equal(event.extensions.gift.id, "gift-2");
  assert.throws(() => events.buildDeliveryDomainEvent({eventType: "GiftCompleted", delivery: {id: "d", status: "delivered"}}), /Unsupported delivery event/);
});

test("legacy records adapt without changing their stored shape", () => {
  const coreDelivery = adapter.fromLegacyDeliveryRecord({
    requestId: "delivery-3",
    deliveryStage: "delivered",
    customerId: "sender-3",
    stripePaymentIntentId: "pi-3",
    businessOrderId: "not-core",
  });
  assert.equal(coreDelivery.deliveryId, "delivery-3");
  assert.equal(coreDelivery.paymentId, "pi-3");
  assert.equal("businessOrderId" in coreDelivery, false);
});

test("platform service contracts reject missing bounded contexts", () => {
  assert.throws(() => services.createPlatformServices({}), /Missing platform services/);
  const platform = Object.fromEntries(services.SERVICE_NAMES.map((name) => [name, {}]));
  const registered = services.createPlatformServices(platform);
  assert.equal(registered.dispatch, platform.dispatch);
  assert.throws(() => services.requireOperation(registered.dispatch, "match"), /not implemented/);
});
