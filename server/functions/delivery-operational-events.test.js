"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {eventIdFor, eventRecord, sanitizeMetadata} = require("./delivery-operational-events");

test("operational event IDs are deterministic and correlation-specific", () => {
  const input = {deliveryId: "delivery-1", eventType: "Completed", correlationId: "completion-1"};
  assert.equal(eventIdFor(input), eventIdFor(input));
  assert.notEqual(eventIdFor(input), eventIdFor({...input, correlationId: "completion-2"}));
});

test("canonical event contains the auditable immutable contract", () => {
  const record = eventRecord({deliveryId: "delivery-1", eventType: "PaymentConfirmed", correlationId: "payment-1", actorType: "system", source: "stripe-webhook", previousState: "requested", newState: "paid"});
  for (const key of ["eventId", "deliveryId", "eventType", "timestamp", "actorType", "actorId", "source", "correlationId", "metadata", "previousState", "newState"]) assert.ok(Object.hasOwn(record, key), key);
  assert.equal(record.immutable, true);
});

test("event metadata removes secrets and bounds nested data", () => {
  const result = sanitizeMetadata({status: "ok", stripeClientSecret: "secret", pushToken: "token", nested: {value: "kept"}});
  assert.deepEqual(result, {status: "ok", nested: {value: "kept"}});
});
