"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {createHealthPlusCheckoutHandler, createHealthPlusBillingPortalHandler} = require("./health-plus")._qaHandlers;

for (const [name, handler] of Object.entries({checkout: createHealthPlusCheckoutHandler, portal: createHealthPlusBillingPortalHandler})) {
  test(`Health+ ${name} preflight permits authenticated App Check clients without invoking a payment`, async () => {
    const headers = {};
    const response = {
      set(key, value) {
headers[key.toLowerCase()] = value;
},
      status(code) {
this.statusCode = code; return this;
},
      send(body) {
this.body = body; return this;
},
    };
    const provider = new Proxy({}, {get() {
throw new Error("Preflight must not call Stripe");
}});
    await handler({method: "OPTIONS", headers: {origin: "https://circumuk.com"}}, response, {stripe: provider});
    assert.equal(response.statusCode, 204);
    const allowed = headers["access-control-allow-headers"].toLowerCase().split(/,\s*/);
    for (const header of ["authorization", "content-type", "x-firebase-appcheck"]) assert.ok(allowed.includes(header));
  });
}
