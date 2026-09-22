"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {createHandlers, createServer, routeName} = require("./cloud-run-rider-delivery-authority");

async function listen(server, run) {
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
    await run(`http://127.0.0.1:${server.address().port}`);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

test("routes expose only the migrated Rider delivery authorities", () => {
  assert.equal(routeName("/completeDelivery"), "completeDelivery");
  assert.equal(routeName("/v1/callable/getAvailableRequests"), "getAvailableRequests");
  assert.equal(routeName("/getAvaliableRequests"), "getAvaliableRequests");
  assert.equal(routeName("/getNearbyRequests"), "getNearbyRequests");
  assert.equal(routeName("/updateDeliveryTrackingStatus"), null);
});

test("handlers preserve the canonical completion and offer cores", async () => {
  const calls = [];
  const db = {marker: "canonical-db"};
  const handlers = createHandlers({db});
  assert.equal(typeof handlers.completeDelivery, "function");
  assert.equal(typeof handlers.getAvailableRequests, "function");
  const server = createServer({dependenciesFactory: () => ({
    verifyIdToken: async (token) => token === "valid-id" ? {uid: "rider-1"} : Promise.reject(Object.assign(new Error("Bad ID token."), {code: "auth/invalid-id-token"})),
    verifyAppCheck: async (token) => token === "valid-app" ? {appId: "rider-app"} : Promise.reject(Object.assign(new Error("Bad App Check token."), {code: "app-check/invalid-argument"})),
    handlers: {
      completeDelivery: async (data, context) => (calls.push(["complete", data, context]), {status: "delivered"}),
      getAvailableRequests: async (data, context) => (calls.push(["offers", data, context]), {riderId: context.auth.uid, nearestRequests: []}),
    },
  })});
  await listen(server, async (url) => {
    let response = await fetch(`${url}/getAvailableRequests`, {method: "POST", headers: {"content-type": "application/json"}, body: JSON.stringify({data: {}})});
    assert.equal(response.status, 401);
    response = await fetch(`${url}/getAvailableRequests`, {method: "POST", headers: {authorization: "Bearer valid-id", "content-type": "application/json"}, body: JSON.stringify({data: {}})});
    assert.equal(response.status, 400);
    response = await fetch(`${url}/getAvailableRequests`, {method: "POST", headers: {authorization: "Bearer valid-id", "x-firebase-appcheck": "valid-app", "content-type": "application/json"}, body: JSON.stringify({data: {}})});
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {result: {riderId: "rider-1", nearestRequests: []}});
    response = await fetch(`${url}/completeDelivery`, {method: "POST", headers: {authorization: "Bearer valid-id", "x-firebase-appcheck": "valid-app", "content-type": "application/json"}, body: JSON.stringify({data: {deliveryId: "delivery-1", deliveryPin: "123456"}})});
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {result: {status: "delivered"}});
  });
  assert.equal(calls.length, 2);
  assert.equal(calls[0][2].auth.uid, "rider-1");
  assert.equal(calls[0][2].app.appId, "rider-app");
  assert.deepEqual(calls[1][1], {deliveryId: "delivery-1", deliveryPin: "123456"});
});

test("health is lazy and reports immutable source provenance", async () => {
  const previous = process.env.CIRCUM_SOURCE_SHA;
  process.env.CIRCUM_SOURCE_SHA = "test-sha";
  const server = createServer({dependenciesFactory: () => {
    throw new Error("health must stay lazy");
  }});
  await listen(server, async (url) => {
    const response = await fetch(`${url}/health`);
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {status: "ok", runtime: "node22", source: "test-sha"});
  });
  if (previous === undefined) delete process.env.CIRCUM_SOURCE_SHA;
  else process.env.CIRCUM_SOURCE_SHA = previous;
});
