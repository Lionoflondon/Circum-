"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {createPaymentFamilyServer, FAMILY_ROUTES} = require("./cloud-run-payment-family");

async function withServer(family, handlers, callback) {
  const server = createPaymentFamilyServer({family, handlers});
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
    await callback(`http://127.0.0.1:${server.address().port}`);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

test("every payment family has unique named routes", () => {
  for (const routes of Object.values(FAMILY_ROUTES)) {
    assert.equal(new Set(routes).size, routes.length);
  }
});

test("payment family wrapper exposes health without invoking finance", async () => {
  const handlers = Object.fromEntries(FAMILY_ROUTES.health_plus.map((name) => [name, () => {
    throw new Error("must not run");
  }]));
  await withServer("health_plus", handlers, async (url) => {
    const response = await fetch(`${url}/healthz`);
    assert.equal(response.status, 200);
    assert.equal((await response.json()).family, "health_plus");
  });
});

test("payment family wrapper rejects cross-family routes", async () => {
  const handlers = Object.fromEntries(FAMILY_ROUTES.tips.map((name) => [name, (_req, res) => res.send({ok: true})]));
  await withServer("tips", handlers, async (url) => {
    const response = await fetch(`${url}/createGiftPayment`, {method: "POST"});
    assert.equal(response.status, 404);
  });
});

test("payment family wrapper preserves callable body and bearer header", async () => {
  const handlers = Object.fromEntries(FAMILY_ROUTES.tips.map((name) => [name, (req, res) => {
    assert.equal(req.header("Authorization"), "Bearer fixture");
    assert.deepEqual(req.body, {data: {deliveryId: "delivery_1", amountPence: 500}});
    res.send({data: {accepted: true}});
  }]));
  await withServer("tips", handlers, async (url) => {
    const response = await fetch(`${url}/submitDeliveryTip`, {
      method: "POST",
      headers: {authorization: "Bearer fixture", "content-type": "application/json"},
      body: JSON.stringify({data: {deliveryId: "delivery_1", amountPence: 500}}),
    });
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {data: {accepted: true}});
  });
});
