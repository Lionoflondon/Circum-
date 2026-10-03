/* eslint-disable max-len, require-jsdoc */
"use strict";
const assert = require("node:assert/strict");
const test = require("node:test");
const {createHandlers} = require("./cloud-run-rider-finance-handlers");
const {createPaymentFamilyServer} = require("./cloud-run-payment-family");
const handlers = createHandlers("rider_payouts");

test("standalone Rider admin routes reject unauthenticated HTTP before any mutation", async () => {
  const server = createPaymentFamilyServer({family: "rider_payouts", handlers});
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
    for (const operation of ["adminReviewRider", "adminReconcileRiderEarnings"]) {
      const response = await fetch(`http://127.0.0.1:${server.address().port}/${operation}`, {
        method: "POST", headers: {"content-type": "application/json"}, body: JSON.stringify({data: {}}),
      });
      assert.equal(response.status, 401, operation);
      assert.equal((await response.json()).error.status, "UNAUTHENTICATED", operation);
    }
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test("standalone Rider admin cores preserve role authorization and validation before writes", async () => {
  const rider = {auth: {uid: "rider-only", token: {role: "rider"}}, app: {appId: "isolated-test"}};
  const admin = {auth: {uid: "approved-admin", token: {role: "super_admin"}}, app: {appId: "isolated-test"}};
  for (const operation of ["adminReviewRider", "adminReconcileRiderEarnings"]) {
    await assert.rejects(handlers[operation].run({}, rider), {code: "permission-denied"}, operation);
    await assert.rejects(handlers[operation].run({}, admin), {code: "invalid-argument"}, operation);
  }
});
