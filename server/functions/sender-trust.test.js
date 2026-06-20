const assert = require("node:assert/strict");
const test = require("node:test");
const {
  rothTopUpPoints,
  isSenderEligibleForRothProgression,
} = require("./sender-trust");

test("awards sender progression points by successful Roth top-up band", () => {
  assert.equal(rothTopUpPoints(10), 1);
  assert.equal(rothTopUpPoints(25), 1);
  assert.equal(rothTopUpPoints(25.01), 2);
  assert.equal(rothTopUpPoints(75), 3);
  assert.equal(rothTopUpPoints(150), 4);
  assert.equal(rothTopUpPoints(300), 5);
  assert.equal(rothTopUpPoints(600), 6);
});

test("does not award Roth purchase progression to rider-only accounts", () => {
  assert.equal(isSenderEligibleForRothProgression({userType: "rider"}), false);
  assert.equal(isSenderEligibleForRothProgression({role: "driver"}), false);
  assert.equal(isSenderEligibleForRothProgression({userType: "sender"}), true);
  assert.equal(isSenderEligibleForRothProgression({}), true);
});
