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
  assert.equal(routeName("/updateDeliveryTrackingStatus"), "updateDeliveryTrackingStatus");
  assert.equal(routeName("/v1/callable/updateDeliveryLiveLocation"), "updateDeliveryLiveLocation");
  assert.equal(routeName("/unreviewedRiderMutation"), null);
});

test("handlers preserve the canonical completion and offer cores", async () => {
  const calls = [];
  const db = {marker: "canonical-db"};
  const handlers = createHandlers({db});
  assert.equal(typeof handlers.completeDelivery, "function");
  assert.equal(typeof handlers.getAvailableRequests, "function");
  assert.equal(typeof handlers.updateDeliveryTrackingStatus, "function");
  assert.equal(typeof handlers.updateDeliveryLiveLocation, "function");
  const server = createServer({dependenciesFactory: () => ({
    verifyIdToken: async (token) => token === "valid-id" ? {uid: "rider-1"} : Promise.reject(Object.assign(new Error("Bad ID token."), {code: "auth/invalid-id-token"})),
    verifyAppCheck: async (token) => token === "valid-app" ? {appId: "rider-app"} : Promise.reject(Object.assign(new Error("Bad App Check token."), {code: "app-check/invalid-argument"})),
    handlers: {
      completeDelivery: async (data, context) => (calls.push(["complete", data, context]), {status: "delivered"}),
      getAvailableRequests: async (data, context) => (calls.push(["offers", data, context]), {riderId: context.auth.uid, nearestRequests: []}),
      updateDeliveryTrackingStatus: async (data, context) => (calls.push(["tracking", data, context]), {status: "navigating_to_pickup"}),
      updateDeliveryLiveLocation: async (data, context) => (calls.push(["location", data, context]), {status: "accepted"}),
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
    response = await fetch(`${url}/updateDeliveryTrackingStatus`, {method: "POST", headers: {authorization: "Bearer valid-id", "x-firebase-appcheck": "valid-app", "content-type": "application/json"}, body: JSON.stringify({data: {deliveryId: "delivery-1", action: "start_heading_to_pickup"}})});
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {result: {status: "navigating_to_pickup"}});
    response = await fetch(`${url}/updateDeliveryLiveLocation`, {method: "POST", headers: {authorization: "Bearer valid-id", "x-firebase-appcheck": "valid-app", "content-type": "application/json"}, body: JSON.stringify({data: {deliveryId: "delivery-1", status: "completed", location: {latitude: 51.5, longitude: -0.12}}})});
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {result: {status: "accepted"}});
    response = await fetch(`${url}/updateDeliveryLiveLocation`, {method: "POST", headers: {authorization: "Bearer valid-id", "x-firebase-appcheck": "valid-app", "content-type": "application/json"}, body: JSON.stringify({data: null})});
    assert.equal(response.status, 400);
  });
  assert.equal(calls.length, 4);
  assert.equal(calls[0][2].auth.uid, "rider-1");
  assert.equal(calls[0][2].app.appId, "rider-app");
  assert.deepEqual(calls[1][1], {deliveryId: "delivery-1", deliveryPin: "123456"});
  assert.deepEqual(calls[2][1], {deliveryId: "delivery-1", action: "start_heading_to_pickup"});
  assert.equal(calls[3][2].auth.uid, "rider-1");
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
