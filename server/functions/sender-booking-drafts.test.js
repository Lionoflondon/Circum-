const test = require("node:test");
const assert = require("node:assert/strict");
const {_private} = require("./sender-booking");

test("sender draft sanitizer keeps only canonical draft fields", () => {
  const draft = _private.sanitizeSenderDraftPayload({
    uid: "attacker",
    completed: true,
    status: "paid",
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
    price: 1,
  });

  assert.equal(draft.version, 1);
  assert.equal(draft.status, "draft");
  assert.equal(draft.completed, false);
  assert.equal(draft.uid, undefined);
  assert.equal(draft.price, undefined);
  assert.equal(draft.pickup.unknown, undefined);
  assert.equal(draft.pickup.address, "10 Downing Street");
  assert.equal(draft.recipient.name, "Ada");
  assert.equal(draft.parcel.fragile, true);
  assert.equal(draft.deliveryOptions.vanguard, true);
  assert.equal(draft.review.amountDue, 12.5);
});

test("sender draft sanitizer defaults unsafe values", () => {
  const draft = _private.sanitizeSenderDraftPayload({
    step: "",
    deliveryOptions: {vanguard: "yes"},
    review: {amountDue: "not-money"},
  });

  assert.equal(draft.step, "pickup");
  assert.equal(draft.status, "draft");
  assert.equal(draft.deliveryOptions.selectedOption, "Standard");
  assert.equal(draft.deliveryOptions.vanguard, false);
  assert.equal(draft.review.amountDue, null);
});
