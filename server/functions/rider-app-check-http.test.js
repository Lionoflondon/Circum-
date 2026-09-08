"use strict";
const {test, before, after, mock} = require("node:test");
const assert = require("node:assert/strict");
const express = require("express");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getAuth} = require("firebase-admin/auth");
const {getAppCheck} = require("firebase-admin/app-check");
let app; let server; let url;
before(async () => {
  app = initializeApp({projectId: "demo-app-check-http"});
  mock.method(getAuth(), "verifyIdToken", async () => ({uid: "rider", role: "rider"}));
  mock.method(getAppCheck(), "verifyToken", async (token) => {
    if (token !== "valid-test-token") throw new Error("Invalid test token");
    return {appId: "test", token: {app_id: "test"}};
  });
  const endpoints = require("./delivery-adjustments");
  endpoints.requestRiderCancellation = require("./rider-cancellation").requestRiderCancellation;
  const service = express(); service.use(express.json());
  for (const name of ["requestRiderCancellation", "reportLoadDiscrepancy", "reviewDeliveryAdjustment", "cancelAdjustedCollection"]) service.post(`/${name}`, endpoints[name]);
  server = service.listen(0, "127.0.0.1");
  await new Promise((resolve) => server.once("listening", resolve));
  url = `http://127.0.0.1:${server.address().port}`;
});
after(async () => {
  mock.restoreAll(); if (server) await new Promise((resolve) => server.close(resolve)); if (app) await deleteApp(app);
});
for (const name of ["requestRiderCancellation", "reportLoadDiscrepancy", "reviewDeliveryAdjustment", "cancelAdjustedCollection"]) {
  test(`${name}: real callable transport rejects missing/invalid App Check and missing auth`, async () => {
    for (const token of [null, "invalid-test-token"]) {
      const response = await fetch(`${url}/${name}`, {method: "POST", headers: {"Content-Type": "application/json", "Authorization": "Bearer test", ...(token ? {"X-Firebase-AppCheck": token} : {})}, body: JSON.stringify({data: {}})});
      assert.equal(response.status, 401);
    }
    const response = await fetch(`${url}/${name}`, {method: "POST", headers: {"Content-Type": "application/json", "X-Firebase-AppCheck": "valid-test-token"}, body: JSON.stringify({data: {}})});
    assert.equal(response.status, 401);
    const valid = await fetch(`${url}/${name}`, {method: "POST", headers: {"Content-Type": "application/json", "Authorization": "Bearer test", "X-Firebase-AppCheck": "valid-test-token"}, body: JSON.stringify({data: {}})});
    // Verified App Check reaches application validation (never the token-rejection path).
    assert.notEqual(valid.status, 401);
  });
}
