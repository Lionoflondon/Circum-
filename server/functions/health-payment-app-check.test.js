"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {initializeApp, getApps} = require("firebase-admin/app");
const {getAuth} = require("firebase-admin/auth");
const {getAppCheck} = require("firebase-admin/app-check");
if (!getApps().length) initializeApp({projectId: "demo-health-app-check"});
const {verifySenderRequest, createHealthPlusCheckoutHandler, createHealthPlusBillingPortalHandler} = require("./health-plus")._qaHandlers;

function response() {
  return {statusCode: 200, set() {}, status(code) {
this.statusCode = code; return this;
}, send(body) {
this.body = body; return this;
}};
}
const validHeaders = {authorization: "Bearer signed-in-user", "x-firebase-appcheck": "attested-app"};
for (const [name, handler] of Object.entries({checkout: createHealthPlusCheckoutHandler, portal: createHealthPlusBillingPortalHandler})) {
  for (const scenario of ["missing-auth", "malformed-auth", "missing-app-check", "empty-app-check", "invalid-app-check", "invalid-auth"]) {
    test(`Health+ ${name} rejects ${scenario} before any provider or database access`, async (t) => {
      let authCalls = 0; let appCalls = 0; let sideEffects = 0;
      t.mock.method(getAuth(), "verifyIdToken", async (token) => {
        authCalls++; assert.equal(token, "signed-in-user");
        if (scenario === "invalid-auth") throw new Error("invalid auth");
        return {uid: "owned-sender", email: "sender@example.invalid"};
      });
      t.mock.method(getAppCheck(), "verifyToken", async (token) => {
        appCalls++; assert.equal(token, "attested-app");
        if (scenario === "invalid-app-check") throw new Error("invalid attestation");
        return {appId: "registered-health-client"};
      });
      const headers = {...validHeaders};
      if (scenario === "missing-auth") delete headers.authorization;
      if (scenario === "malformed-auth") headers.authorization = "untrusted";
      if (scenario === "missing-app-check") delete headers["x-firebase-appcheck"];
      if (scenario === "empty-app-check") headers["x-firebase-appcheck"] = " ";
      const forbidden = new Proxy({}, {get() {
sideEffects++; throw new Error("Unexpected financial/database access");
}});
      const res = response();
      await handler({method: "POST", headers, body: {bookingId: "owned-booking", profileId: "owned-sender"}}, res, {db: forbidden, stripe: forbidden});
      assert.equal(res.statusCode, 401);
      assert.equal(res.body.code, "unauthenticated");
      assert.equal(sideEffects, 0);
      assert.equal(authCalls, scenario === "invalid-auth" ? 1 : 0);
      assert.equal(appCalls, ["invalid-auth", "invalid-app-check"].includes(scenario) ? 1 : 0);
    });
  }
}

test("valid App Check plus Auth returns only the authenticated Sender identity", async (t) => {
  const order = [];
  t.mock.method(getAppCheck(), "verifyToken", async (token) => {
order.push("app"); assert.equal(token, "attested-app"); return {appId: "registered-app"};
});
  t.mock.method(getAuth(), "verifyIdToken", async (token) => {
order.push("auth"); assert.equal(token, "signed-in-user"); return {uid: "owned-sender", email: "sender@example.invalid"};
});
  const result = await verifySenderRequest({headers: validHeaders, body: {senderId: "someone-else"}});
  assert.deepEqual(result, {uid: "owned-sender", email: "sender@example.invalid"});
  assert.deepEqual(order, ["app", "auth"]);
});
