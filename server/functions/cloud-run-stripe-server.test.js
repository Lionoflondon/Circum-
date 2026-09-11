/* eslint-disable max-len */
"use strict";

const assert = require("node:assert/strict");
const http = require("node:http");
const test = require("node:test");
const {createServer} = require("./cloud-run-stripe-server");

async function withServer(processor, run) {
  const server = createServer({processorFactory: () => processor});
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
    await run(server.address().port);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

function request(port, {method = "GET", path = "/health", headers = {}, body = null} = {}) {
  return new Promise((resolve, reject) => {
    const req = http.request({hostname: "127.0.0.1", port, method, path, headers}, (res) => {
      const chunks = [];
      res.on("data", (chunk) => chunks.push(chunk));
      res.on("end", () => resolve({status: res.statusCode, body: Buffer.concat(chunks).toString()}));
    });
    req.on("error", reject);
    if (body) req.write(body);
    req.end();
  });
}

test("health is safe and webhook preserves exact raw bytes", async () => {
  const seen = [];
  await withServer(async (input) => {
    seen.push(input);
    return {status: 200, body: {received: true}};
  }, async (port) => {
    const health = await request(port);
    assert.equal(health.status, 200);
    assert.deepEqual(JSON.parse(health.body), {status: "ok", runtime: "node22", version: "unknown"});
    const raw = Buffer.from("{ \"id\" : \"evt_raw\" }");
    const webhook = await request(port, {method: "POST", path: "/stripe/webhook", headers: {"content-type": "application/json", "stripe-signature": "sig_fixture", "content-length": raw.length}, body: raw});
    assert.equal(webhook.status, 200);
    assert.deepEqual(seen[0].rawBody, raw);
    assert.equal(seen[0].signature, "sig_fixture");
  });
});

test("webhook rejects bodies larger than one MiB without invoking the processor", async () => {
  let calls = 0;
  await withServer(async () => {
 calls += 1; return {status: 200, body: {}};
}, async (port) => {
    const body = Buffer.alloc((1024 * 1024) + 1, "x");
    const result = await request(port, {method: "POST", path: "/stripe/webhook", headers: {"content-type": "application/json", "stripe-signature": "sig_fixture", "content-length": body.length}, body});
    assert.equal(result.status, 413);
  });
  assert.equal(calls, 0);
});

test("webhook rejects wrong method, path and content type before processor invocation", async () => {
  let calls = 0;
  await withServer(async () => {
 calls += 1; return {status: 200, body: {}};
}, async (port) => {
    assert.equal((await request(port, {path: "/debug"})).status, 404);
    assert.equal((await request(port, {path: "/stripe/webhook"})).status, 405);
    assert.equal((await request(port, {method: "POST", path: "/stripe/webhook", headers: {"content-type": "text/plain"}, body: "{}"})).status, 415);
  });
  assert.equal(calls, 0);
});

test("20 simultaneous first requests initialize one shared processor", async () => {
  let factoryCalls = 0;
  const server = createServer({processorFactory: async () => {
    factoryCalls += 1;
    await new Promise((resolve) => setTimeout(resolve, 20));
    return async () => ({status: 200, body: {received: true}});
  }});
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
    const port = server.address().port;
    const raw = Buffer.from("{}");
    const responses = await Promise.all(Array.from({length: 20}, () => request(port, {method: "POST", path: "/stripe/webhook", headers: {"content-type": "application/json", "stripe-signature": "sig_fixture", "content-length": raw.length}, body: raw})));
    assert.deepEqual(new Set(responses.map((response) => response.status)), new Set([200]));
    assert.equal(factoryCalls, 1);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test("failed initialization is retained without poisoning later requests", async () => {
  let factoryCalls = 0;
  const originalError = new Error("controlled initialization failure");
  const server = createServer({processorFactory: () => {
    factoryCalls += 1;
    throw originalError;
  }});
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
    const port = server.address().port;
    const raw = Buffer.from("{}");
    for (let attempt = 0; attempt < 3; attempt += 1) {
      const response = await request(port, {method: "POST", path: "/stripe/webhook", headers: {"content-type": "application/json", "stripe-signature": "sig_fixture", "content-length": raw.length}, body: raw});
      assert.equal(response.status, 500);
    }
    assert.equal(factoryCalls, 1);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});
