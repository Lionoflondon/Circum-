/* eslint-disable max-len, require-jsdoc */
"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const Stripe = require("stripe");
const {createWebsiteRothServer} = require("./cloud-run-website-roth");
test("HTTP rejects missing App Check and forged Stripe events; accepts correctly signed fixture", async () => {
  const stripe = new Stripe("sk_test_local_fixture");
  const secret = "whsec_local_fixture_only";
  let finalized = 0;
  const service = {request: async () => ({ok: true}), finalize: async () => {
finalized++;
}};
  const server = createWebsiteRothServer({service, stripe, webhookSecret: secret, verifyAppCheck: async (token) => {
if (token !== "test-only-valid") throw new Error("invalid");
}});
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const url = `http://127.0.0.1:${server.address().port}`;
  try {
    assert.equal((await fetch(`${url}/api/roth/request`, {method: "POST", body: "{}"})).status, 503);
    const payload = JSON.stringify({id: "evt_test", type: "checkout.session.completed", data: {object: {id: "cs_test"}}});
    assert.equal((await fetch(`${url}/webhook`, {method: "POST", body: payload, headers: {"stripe-signature": "forged"}})).status, 400);
    assert.equal(finalized, 0);
    const signature = stripe.webhooks.generateTestHeaderString({payload, secret});
    assert.equal((await fetch(`${url}/webhook`, {method: "POST", body: payload, headers: {"stripe-signature": signature}})).status, 200);
    assert.equal(finalized, 1);
  } finally {
await new Promise((resolve) => server.close(resolve));
}
});
