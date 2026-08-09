"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const refunds = require("./scheduled-road-charge-refunds");

test("cash exception is support-authorized and exported as a callable", () => {
  const source = fs.readFileSync(path.join(__dirname, "scheduled-road-charge-refunds.js"), "utf8");
  const index = fs.readFileSync(path.join(__dirname, "index.js"), "utf8");
  assert.equal(typeof refunds.settleEntitlementToCash, "function");
  assert.match(source, /requireAdmin\(context, "Support or administrator access is required\."\)/);
  assert.match(source, /const settleScheduledRoadChargeCashRefund = functions\.https\.onCall/);
  assert.match(index, /exports\.settleScheduledRoadChargeCashRefund/);
});

test("ordinary actor cannot settle cash or mutate through the pure transaction path", async () => {
  const result = await refunds.settleEntitlementToCash({
    entitlementId: "cash-unauthorized",
    customerRequestReference: "support-case-1",
    cashRefundReference: "cash-ref-1",
    actor: {authorized: false, uid: "customer-1"},
    db: {
      runTransaction: async () => {
        throw new Error("transaction must not run");
      },
    },
  });
  assert.deepEqual(result, {settled: false, reason: "support_authorization_required", entitlementId: "cash-unauthorized"});
});

test("authorized cash settlement requires a real support ticket reference", async () => {
  const result = await refunds.settleEntitlementToCash({
    entitlementId: "cash-missing-ticket",
    customerRequestReference: "missing-ticket",
    cashRefundReference: "cash-ref-2",
    actor: {authorized: true, uid: "support-agent-1"},
    db: {
      collection: (name) => ({doc: (id) => ({name, id})}),
      runTransaction: async (callback) => callback({
        get: async (ref) => ref.name === "roadChargeRefundEntitlements" ? {
          exists: true,
          data: () => ({
            state: refunds.STATES.eligible,
            refundablePence: 900,
            policyVersion: refunds.REFUND_POLICY_VERSION,
            deliveryId: "delivery-1",
          }),
        } : {exists: false},
      }),
    },
  });
  assert.deepEqual(result, {settled: false, reason: "support_request_not_found", entitlementId: "cash-missing-ticket"});
});
