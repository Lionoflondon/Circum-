"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {createServer} = require("./cloud-run-rider-policy-server");

async function withServer(run) {
  const server = createServer({processorFactory: () => async (body) => ({outcome: "NO_OP", riderId: body.riderId})});
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
    await run(`http://127.0.0.1:${server.address().port}`);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

test("health and recompute transport are bounded", async () => withServer(async (url) => {
  let response = await fetch(`${url}/health`);
  assert.equal(response.status, 200);
  response = await fetch(`${url}/v1/recompute`, {method: "POST", headers: {"content-type": "application/json"}, body: JSON.stringify({riderId: "qa-rider"})});
  assert.equal(response.status, 200);
  assert.equal((await response.json()).outcome, "NO_OP");
  response = await fetch(`${url}/v1/recompute`, {method: "POST", headers: {"content-type": "application/json"}, body: "x".repeat(17000)});
  assert.equal(response.status, 413);
}));
