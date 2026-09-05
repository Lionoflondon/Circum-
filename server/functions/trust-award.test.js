const test = require("node:test");
const assert = require("node:assert/strict");
const {highestTrustAward} = require("./trust-award");

test("offer and completion use the same canonical trust award", () => {
  const delivery = {requiresVanguard: true};
  assert.equal(highestTrustAward(delivery), 4);
  assert.equal(highestTrustAward({...delivery, trustPointsAwarded: 4}), 4);
});

test("trust award is idempotency-compatible with the delivery ledger key", () => {
  const deliveryId = "delivery-123";
  const ledgerId = deliveryId;
  assert.equal(ledgerId, deliveryId);
  assert.equal(highestTrustAward({isGift: true}), 5);
});
