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
    iris: {confidence: "High", recommendedVehicle: "Motorbike"},
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

test("sender draft expiry detects stale drafts", () => {
  const expired = {
    expiresAt: {toMillis: () => Date.now() - 1000},
  };
  const active = {
    expiresAt: {toMillis: () => Date.now() + 1000},
  };

  assert.equal(_private.draftExpired(expired), true);
  assert.equal(_private.draftExpired(active), false);
  assert.equal(_private.draftExpired({}), false);
});

test("sender draft inactivity detects drafts abandoned for over ten minutes", () => {
  const abandoned = {
    updatedAt: {toMillis: () => Date.now() - 11 * 60 * 1000},
  };
  const fresh = {
    updatedAt: {toMillis: () => Date.now() - 9 * 60 * 1000},
  };

  assert.equal(_private.draftInactive(abandoned), true);
  assert.equal(_private.draftInactive(fresh), false);
  assert.equal(_private.DRAFT_INACTIVITY_MINUTES, 10);
});

test("delivery idempotency key input is stable", () => {
  const a = _private.stableId("uid:draft:quote:session");
  const b = _private.stableId("uid:draft:quote:session");
  const c = _private.stableId("uid:draft:quote:other");
  assert.equal(a, b);
  assert.notEqual(a, c);
  assert.equal(a.length, 32);
});

test("sender quote charges distance in miles", () => {
  const quote = _private.quotePayload({
    selectedSpeed: "Standard",
    distanceMiles: 3,
    weightKg: 2,
    parcel: {itemName: "Book", weightKg: 2},
  }, "sender-test");
  const distanceLine = quote.lineItems.find((item) => item.key === "distance");
  const speedLine = quote.lineItems.find((item) => item.key === "speed_adjustment");

  assert.equal(quote.distanceMiles, 3);
  assert.equal(distanceLine.amount, 4.5);
  assert.equal(speedLine.amount, 0);
  assert.equal(quote.total, 9.5);
});

test("sender quote charges two pounds for car vehicle", () => {
  const quote = _private.quotePayload({
    selectedSpeed: "Standard",
    distanceMiles: 3,
    weightKg: 2,
    selectedVehicle: "Car",
    parcel: {itemName: "Printer", weightKg: 2},
  }, "sender-test");
  const vehicleLine = quote.lineItems.find((item) => item.key === "vehicle");

  assert.equal(quote.selectedVehicle, "car");
  assert.equal(vehicleLine.amount, 2);
  assert.equal(quote.vehicleSurcharge, 2);
  assert.equal(quote.total, 11.5);
});

test("sender express surcharge is five pounds or twenty percent", () => {
  const shortQuote = _private.quotePayload({
    selectedSpeed: "Express",
    distanceMiles: 3,
    weightKg: 2,
    parcel: {itemName: "Book", weightKg: 2},
  }, "sender-test");
  const longQuote = _private.quotePayload({
    selectedSpeed: "Express",
    distanceMiles: 40,
    weightKg: 2,
    parcel: {itemName: "Book", weightKg: 2},
  }, "sender-test");

  assert.equal(shortQuote.lineItems.find((item) => item.key === "speed_adjustment").amount, 5);
  assert.equal(shortQuote.total, 14.5);
  assert.equal(longQuote.lineItems.find((item) => item.key === "speed_adjustment").amount, 15.4);
  assert.equal(longQuote.total, 92.4);
});
