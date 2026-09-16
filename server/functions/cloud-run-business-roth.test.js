"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {createBusinessRothServer} = require("./cloud-run-business-roth");

async function withServer(callable, callback) {
  const server = createBusinessRothServer(callable);
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
    await callback(`http://127.0.0.1:${server.address().port}`);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

test("Business Roth Cloud Run wrapper exposes health without invoking payment code", async () => {
  let invoked = 0;
  await withServer(() => invoked++, async (url) => {
    const response = await fetch(`${url}/healthz`);
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {status: "ok", service: "business-roth-checkout"});
    assert.equal(invoked, 0);
  });
});

test("Business Roth Cloud Run wrapper preserves callable request headers and body", async () => {
  await withServer((req, res) => {
    assert.equal(req.headers.authorization, "Bearer test-token");
    assert.deepEqual(req.body, {data: {businessId: "business_1", amount: 25000}});
    res.status(200).send({data: {accepted: true}});
  }, async (url) => {
    const response = await fetch(url, {
      method: "POST",
      headers: {authorization: "Bearer test-token", "content-type": "application/json"},
      body: JSON.stringify({data: {businessId: "business_1", amount: 25000}}),
    });
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {data: {accepted: true}});
  });
});
