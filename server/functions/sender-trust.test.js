/* eslint-disable max-len */
const assert = require("node:assert/strict");
const test = require("node:test");
const {
  tierForPoints,
  normalizeTier,
  rothTopUpPoints,
  isSenderEligibleForRothProgression,
  tokenHasTrustAdminRole,
  trustActionRequest,
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

test("Sender Trust keeps canonical backend tier thresholds", () => {
  assert.equal(tierForPoints(0), "new_sender");
  assert.equal(tierForPoints(25), "active_sender");
  assert.equal(tierForPoints(100), "regular_sender");
  assert.equal(tierForPoints(300), "priority_sender");
  assert.equal(tierForPoints(750), "platinum_sender");
  assert.equal(normalizeTier("priority sender", 0), "priority_sender");
  assert.equal(normalizeTier("legacy-unknown", 300), "priority_sender");
});

test("Sender Trust admin callable accepts customer-editing Admin roles only", () => {
  assert.equal(tokenHasTrustAdminRole({admin: true}), true);
  assert.equal(tokenHasTrustAdminRole({role: "operations_admin"}), true);
  assert.equal(tokenHasTrustAdminRole({adminRole: "support_agent"}), true);
  assert.equal(tokenHasTrustAdminRole({roles: ["sender"]}), false);
  assert.equal(tokenHasTrustAdminRole({role: "finance_admin"}), false);
});

test("Sender Trust admin request requires supported action and reason", () => {
  assert.deepEqual(trustActionRequest({
    senderId: "sender-1",
    action: "award",
    points: -5,
    reason: "Manual trust correction",
  }), {
    senderId: "sender-1",
    action: "award",
    reason: "Manual trust correction",
    points: 5,
    tier: "",
  });
  assert.throws(
      () => trustActionRequest({senderId: "sender-1", action: "award", points: 5}),
      (error) => error.code === "invalid-argument",
  );
  assert.throws(
      () => trustActionRequest({senderId: "sender-1", action: "award", reason: "No points"}),
      (error) => error.code === "invalid-argument",
  );
  assert.throws(
      () => trustActionRequest({senderId: "sender-1", action: "promote", reason: "No tier"}),
      (error) => error.code === "invalid-argument",
  );
});
