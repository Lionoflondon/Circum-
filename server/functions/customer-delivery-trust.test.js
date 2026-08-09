"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const {customerEvent, ownsDelivery, receipt} = require("./customer-delivery-trust")._private;

function doc(id, data) {
  return {id, data: () => data};
}

test("customer timeline maps safe milestones and suppresses internal operations", () => {
  assert.equal(customerEvent(doc("a", {eventType: "PaymentConfirmed"})).label, "Payment confirmed");
  assert.equal(customerEvent(doc("b", {eventType: "IncidentCreated", metadata: {riskScore: 99}})), null);
  assert.equal(customerEvent(doc("c", {eventType: "GPSRiskFlag"})), null);
});

test("customer trust requires canonical delivery ownership", () => {
  assert.equal(ownsDelivery({senderId: "sender-1"}, "sender-1"), true);
  assert.equal(ownsDelivery({senderId: "sender-2"}, "sender-1"), false);
  const source = fs.readFileSync("customer-delivery-trust.js", "utf8");
  assert.match(source, /enforceAppCheck: true/);
  assert.match(source, /!ownsDelivery/);
});

test("receipt uses immutable quote snapshot and excludes provider identifiers", () => {
  const result = receipt({
    deliveryReference: "CIRCUM-1234", paidAmount: 27.23, paymentStatus: "paid",
    paymentMethod: "card", vatAmount: 4.54,
    pricingBreakdown: {canonicalQuoteSnapshot: {lineItems: [{label: "Central London fee", amount: 9}], total: 27.23}},
    stripePaymentIntentId: "pi_private", stripeCheckoutSessionId: "cs_private",
  }, "delivery-1");
  assert.equal(result.amountPaid, 27.23);
  assert.equal(result.vatAmount, 4.54);
  assert.deepEqual(result.lineItems, [{label: "Central London fee", amount: 9}]);
  assert.equal(JSON.stringify(result).includes("pi_private"), false);
  assert.equal(JSON.stringify(result).includes("cs_private"), false);
});
