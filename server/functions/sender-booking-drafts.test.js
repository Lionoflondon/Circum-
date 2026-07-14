const test = require("node:test");
const assert = require("node:assert/strict");
const {_private} = require("./sender-booking");

test("sender draft sanitizer keeps only canonical draft fields", () => {
  const saved = _private.sanitizeSenderDraftPayload({
    schemaVersion: 1,
    baseRevision: 0,
    draft: {
    step: "recipient",
    pickup: {address: "10 Downing Street", unknown: "x"},
    dropoff: {address: "Buckingham Palace"},
    recipient: {name: "Ada", phone: "+447700900123", deliveryNotes: "Ring bell"},
    deliveryTime: {type: "scheduled", scheduledDate: "2026-08-01"},
    parcel: {itemName: "Documents", fragile: true, highValue: true},
    iris: {confidence: "High", recommendedVehicle: "Bike"},
    deliveryOptions: {selectedOption: "Express", vanguard: true},
    review: {amountDue: "12.50"},
    paymentMethod: {type: "card", paymentMethodId: "pm_123", rothEnabled: true},
    },
  });
  const draft = saved.draft;

  assert.equal(saved.schemaVersion, 1);
  assert.equal(saved.baseRevision, 0);
  assert.equal(draft.schemaVersion, 1);
  assert.equal(draft.status, "draft");
  assert.equal(draft.completed, false);
  assert.equal(draft.pickup.unknown, undefined);
  assert.equal(draft.pickup.address, "10 Downing Street");
  assert.equal(draft.recipient.name, "Ada");
  assert.equal(draft.parcel.fragile, true);
  assert.equal(draft.deliveryOptions.vanguard, true);
  assert.equal(draft.review.amountDue, 12.5);
});

test("sender draft sanitizer defaults unsafe values", () => {
  const draft = _private.sanitizeSenderDraftPayload({schemaVersion: 1, draft: {}}).draft;

  assert.equal(draft.step, "pickup");
  assert.equal(draft.status, "draft");
  assert.equal(draft.deliveryOptions.selectedOption, "Standard");
  assert.equal(draft.deliveryOptions.vanguard, false);
  assert.equal(draft.review.amountDue, null);
});

test("sender draft rejects unknown top-level fields", () => {
  assert.throws(() => _private.sanitizeSenderDraftPayload({
    schemaVersion: 1,
    draft: {step: "pickup", unexpected: true},
  }), /Unsupported draft field/);
});

test("sender draft rejects forbidden payment and verification fields", () => {
  assert.throws(() => _private.sanitizeSenderDraftPayload({
    schemaVersion: 1,
    draft: {
      step: "payment",
      paymentMethod: {clientSecret: "pi_secret"},
    },
  }), /cannot be stored/);
  assert.throws(() => _private.sanitizeSenderDraftPayload({
    schemaVersion: 1,
    draft: {
      recipient: {senderPin: "1234"},
    },
  }), /cannot be stored/);
});

test("sender draft rejects invalid enums and oversized payloads", () => {
  assert.throws(() => _private.sanitizeSenderDraftPayload({
    schemaVersion: 1,
    draft: {step: "backendDebug"},
  }), /step is not supported/);
  assert.throws(() => _private.sanitizeSenderDraftPayload({
    schemaVersion: 1,
    draft: {deliveryOptions: {selectedOption: "Hyperdrive"}},
  }), /Delivery option is not supported/);
  assert.throws(() => _private.sanitizeSenderDraftPayload({
    schemaVersion: 1,
    draft: {parcel: {description: "x".repeat(40000)}},
  }), /too large/);
});

test("sender draft rejects unsupported future schema", () => {
  assert.throws(() => _private.sanitizeSenderDraftPayload({
    schemaVersion: 999,
    draft: {step: "pickup"},
  }), /newer version/);
});

test("delivery idempotency key input is stable", () => {
  const a = _private.stableId("uid:draft:quote:session");
  const b = _private.stableId("uid:draft:quote:session");
  const c = _private.stableId("uid:draft:quote:other");
  assert.equal(a, b);
  assert.notEqual(a, c);
  assert.equal(a.length, 32);
});
