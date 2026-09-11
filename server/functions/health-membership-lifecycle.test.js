const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const lifecycle = require("./health-membership-lifecycle");
const healthCore = fs.readFileSync(path.join(__dirname, "health-plus-core.js"), "utf8");
const webhookCore = fs.readFileSync(path.join(__dirname, "stripe-webhook-core.js"), "utf8");

test("Health+ membership maps Stripe lifecycle states to product entitlements", () => {
  assert.equal(lifecycle.membershipStatus({status: "active"}), "active");
  assert.equal(lifecycle.membershipStatus({status: "past_due"}), "past_due");
  assert.equal(lifecycle.membershipStatus({status: "unpaid"}), "unpaid");
  assert.equal(lifecycle.membershipStatus({status: "canceled"}), "canceled");
  assert.equal(lifecycle.membershipStatus({status: "active", pause_collection: {behavior: "void"}}), "paused");
});

test("Health+ lifecycle routes every required Stripe event through an event claim", () => {
  assert.match(webhookCore, /customer\.subscription\.created[\s\S]*customer\.subscription\.updated[\s\S]*customer\.subscription\.deleted/);
  assert.match(webhookCore, /invoice\.paid[\s\S]*invoice\.payment_failed/);
  assert.match(webhookCore, /handleHealthMembershipCheckoutSession/);
  assert.match(healthCore, /subscription_data = \{metadata: \{\.\.\.params\.metadata\}\}/);
  const source = fs.readFileSync(path.join(__dirname, "health-membership-lifecycle.js"), "utf8");
  assert.match(source, /healthPlusMembershipEvents/);
  assert.match(source, /transaction\.create\(eventRef/);
  assert.match(source, /if \(\(await transaction\.get\(eventRef\)\)\.exists\)/);
});

test("Health+ invoice supports Stripe's nested subscription reference", () => {
  assert.equal(lifecycle.invoiceSubscriptionId({
    parent: {subscription_details: {subscription: "sub_nested"}},
  }), "sub_nested");
});
