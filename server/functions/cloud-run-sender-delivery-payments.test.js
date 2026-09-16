"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {createSenderDeliveryPaymentsServer, ROUTES} = require("./cloud-run-sender-delivery-payments");

function handlers(observe = () => {}) {
  return Object.fromEntries(Object.values(ROUTES).map((name) => [name, (req, res) => {
    observe(name, req);
    res.status(200).send({data: {route: name}});
  }]));
}

async function withServer(routeHandlers, callback) {
  const server = createSenderDeliveryPaymentsServer(routeHandlers);
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
    await callback(`http://127.0.0.1:${server.address().port}`);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

test("Sender delivery payment wrapper exposes health without invoking payment code", async () => {
  let invoked = 0;
  process.env.STRIPE_MODE = "live";
  await withServer(handlers(() => invoked++), async (url) => {
    const response = await fetch(`${url}/healthz`);
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {status: "ok", service: "sender-delivery-payments", mode: "live"});
    assert.equal(invoked, 0);
  });
});

for (const [path, expectedRoute] of Object.entries(ROUTES)) {
  test(`Sender delivery payment wrapper routes ${path} and preserves callable input`, async () => {
    await withServer(handlers((route, req) => {
      assert.equal(route, expectedRoute);
      assert.equal(req.header("Authorization"), "Bearer sender-token");
      assert.deepEqual(req.body, {data: {quoteId: "quote_1"}});
    }), async (url) => {
      const response = await fetch(`${url}${path}`, {
        method: "POST",
        headers: {authorization: "Bearer sender-token", "content-type": "application/json"},
        body: JSON.stringify({data: {quoteId: "quote_1"}}),
      });
      assert.equal(response.status, 200);
      assert.deepEqual(await response.json(), {data: {route: expectedRoute}});
    });
  });
}

test("Sender delivery payment wrapper rejects unknown and non-POST routes", async () => {
  await withServer(handlers(), async (url) => {
    assert.equal((await fetch(`${url}/unknown`)).status, 404);
    assert.equal((await fetch(`${url}/createSenderPaymentSession`)).status, 405);
  });
});
