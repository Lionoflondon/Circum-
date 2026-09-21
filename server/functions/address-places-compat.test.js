"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const compat = require("./address-places-compat");

test("legacy callable names are Gen 2 facades with App Check and one secret", () => {
  assert.equal(compat.callableOptions().enforceAppCheck, true);
  for (const name of ["searchFreeUkAddresses", "resolveUkAddressPlace"]) {
    const endpoint = compat[name].__endpoint;
    assert.equal(endpoint.platform, "gcfv2");
    assert.deepEqual(endpoint.region, ["us-central1"]);
    assert.deepEqual(endpoint.secretEnvironmentVariables, [{key: "BACKEND_GOOGLE_PLACES_API_KEY"}]);
    assert.deepEqual(endpoint.callableTrigger, {});
    assert.equal(endpoint.maxInstances, 5);
    assert.equal(endpoint.concurrency, 20);
  }
});

test("compatibility module cannot recreate a Gen 1 address function", () => {
  const source = require("node:fs").readFileSync(require.resolve("./address-places-compat"), "utf8");
  assert.match(source, /firebase-functions\/v2\/https/);
  assert.doesNotMatch(source, /firebase-functions\/v1/);
  assert.doesNotMatch(source, /\.https\.onCall/);
});
