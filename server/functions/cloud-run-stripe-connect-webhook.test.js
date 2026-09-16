"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const http = require("node:http");
const {createServer} = require("./cloud-run-stripe-connect-webhook");

function request(server, {method = "GET", path = "/health", headers = {}, body = ""} = {}) {
  return new Promise((resolve, reject) => {
    const address = server.address();
    const req = http.request({host: "127.0.0.1", port: address.port, method, path, headers}, (res) => {
      const chunks = [];
      res.on("data", (chunk) => chunks.push(chunk));
      res.on("end", () => resolve({status: res.statusCode, body: Buffer.concat(chunks).toString("utf8")}));
    });
    req.on("error", reject);
    req.end(body);
  });
}

test("Connect webhook health is safe and exposes source metadata", async (t) => {
  process.env.STRIPE_MODE = "live";
  process.env.CIRCUM_SOURCE_SHA = "fixture-sha";
  const server = createServer({handlerFactory: () => {
    throw new Error("must not initialize handler");
  }}).listen(0);
  t.after(() => server.close());
  const result = await request(server);
  assert.equal(result.status, 200);
  assert.deepEqual(JSON.parse(result.body), {status: "ok", service: "stripe-connect-webhook", runtime: "node22", mode: "live", source: "fixture-sha"});
});

test("Connect webhook preserves raw bytes and delegates only the intended route", async (t) => {
  const calls = [];
  const server = createServer({handlerFactory: () => async (req, res) => {
    calls.push({url: req.url, rawBody: req.rawBody});
    res.status(200).send("received");
  }}).listen(0);
  t.after(() => server.close());
  const raw = Buffer.from("{\"id\":\"evt_fixture\",\"nested\":\"é\"}");
  const result = await request(server, {method: "POST", path: "/stripe/connect-webhook", headers: {"content-type": "application/json", "content-length": raw.length}, body: raw});
  assert.equal(result.status, 200);
  assert.equal(result.body, "received");
  assert.equal(calls.length, 1);
  assert.deepEqual(calls[0].rawBody, raw);
});

test("Connect webhook rejects wrong method, content type and oversized body", async (t) => {
  const server = createServer({handlerFactory: async () => {
    throw new Error("must not initialize handler");
  }}).listen(0);
  t.after(() => server.close());
  assert.equal((await request(server, {path: "/stripe/connect-webhook"})).status, 405);
  assert.equal((await request(server, {method: "POST", path: "/stripe/connect-webhook", headers: {"content-type": "text/plain"}, body: "{}"})).status, 415);
  const oversized = Buffer.alloc(1024 * 1024 + 1, "x");
  assert.equal((await request(server, {method: "POST", path: "/stripe/connect-webhook", headers: {"content-type": "application/json", "content-length": oversized.length}, body: oversized})).status, 413);
});
