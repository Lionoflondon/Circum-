"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {createServer, createHandlers, qaFaultModeFor} = require("./cloud-run-iris");
const {syntheticParcelPng} = require("./qa-iris-certification");

test("IRIS callable security and safe compliance", async () => {
  const handlers = createHandlers({examples: async () => [], db: {}});
  const server = createServer({dependenciesFactory: () => ({
    verifyIdToken: async (token) => token === "valid" ? {uid: "qa_sender"} : Promise.reject(Object.assign(new Error("Invalid token"), {code: "auth/invalid-id-token"})),
    verifyAppCheck: async (token) => token === "valid" ? {} : Promise.reject(Object.assign(new Error("Invalid App Check"), {code: "app-check/invalid-argument"})),
    handlers,
  })});
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
    const url = `http://127.0.0.1:${server.address().port}/analyseIris`;
    const call = async (auth, appCheck, data) => {
      const response = await fetch(url, {method: "POST", headers: {"content-type": "application/json", ...(auth ? {authorization: `Bearer ${auth}`} : {}), ...(appCheck ? {"x-firebase-appcheck": appCheck} : {})}, body: JSON.stringify({data})});
      return {status: response.status, body: await response.json()};
    };
    assert.equal((await call(null, null, {})).status, 401);
    assert.equal((await call("valid", null, {})).status, 400);
    assert.equal((await call("valid", "invalid", {})).status, 401);
    assert.equal((await call("invalid", "valid", {})).status, 401);
    const allowed = await call("valid", "valid", {description: "sealed parcel", declaredWeightText: "2 kg"});
    assert.equal(allowed.status, 200);
    assert.equal(allowed.body.result.compliance.status, "allowed");
    const prohibited = await call("valid", "valid", {description: "weed", declaredWeightText: "1 kg"});
    assert.equal(prohibited.status, 200);
    assert.equal(prohibited.body.result.compliance.status, "prohibited");
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test("QA fault injection requires the private TEST allowlist", () => {
  const env = {
    GCLOUD_PROJECT: "circum-2797c",
    STRIPE_MODE: "TEST",
    QA_LIFECYCLE_ENABLED: "true",
    CIRCUM_QA_CERTIFICATION_CREDENTIALS: JSON.stringify({identities: {
      admin: {uid: "qa_admin"}, sender: {uid: "qa_sender"}, rider: {uid: "qa_rider"},
    }}),
  };
  assert.equal(qaFaultModeFor({data: {qaFaultMode: "unavailable"}, uid: "qa_sender", env}), "unavailable");
  assert.throws(() => qaFaultModeFor({data: {qaFaultMode: "unavailable"}, uid: "ordinary", env}), /not permitted/);
  assert.throws(() => qaFaultModeFor({data: {qaFaultMode: "unknown"}, uid: "qa_sender", env}), /Unsupported/);
  assert.throws(() => qaFaultModeFor({data: {qaFaultMode: "unavailable"}, uid: "qa_sender", env: {...env, STRIPE_MODE: "LIVE"}}), /not permitted/);
});

test("deployed QA failure is bounded and sanitized", async () => {
  const server = createServer({
    env: {
      GCLOUD_PROJECT: "circum-2797c",
      STRIPE_MODE: "TEST",
      QA_LIFECYCLE_ENABLED: "true",
      CIRCUM_QA_CERTIFICATION_CREDENTIALS: JSON.stringify({identities: {sender: {uid: "qa_sender"}}}),
    },
    dependenciesFactory: () => ({
      verifyIdToken: async () => ({uid: "qa_sender"}),
      verifyAppCheck: async () => ({}),
      handlers: {
        analyseParcelPhotoForIris: async () => {
          throw new Error("provider should not run");
        },
      },
    }),
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
    const response = await fetch(`http://127.0.0.1:${server.address().port}/analyseParcelPhotoForIris`, {method: "POST", headers: {"content-type": "application/json", authorization: "Bearer valid", "x-firebase-appcheck": "valid"}, body: JSON.stringify({data: {qaFaultMode: "unavailable"}})});
    assert.equal(response.status, 503);
    const payload = await response.json();
    assert.equal(payload.error.status, "UNAVAILABLE");
    assert.doesNotMatch(JSON.stringify(payload), /provider should not run/);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test("IRIS photo route writes only the caller-scoped canonical analysis", async () => {
  const writes = [];
  const db = {collection(name) {
    assert.equal(name, "irisPhotoAnalyses");
    return {doc(id) {
      return {async set(value) {
        writes.push({id, value});
      }};
    }};
  }};
  const handlers = createHandlers({db, examples: async () => []});
  const data = {imageBase64: syntheticParcelPng().toString("base64"), contentType: "image/png", description: "sealed cardboard parcel", declaredWeightText: "2 kg"};
  const first = await handlers.analyseParcelPhotoForIris(data, {auth: {uid: "qa_sender"}});
  const replay = await handlers.analyseParcelPhotoForIris(data, {auth: {uid: "qa_sender"}});
  assert.equal(first.analysisId, replay.analysisId);
  assert.equal(first.imageHash, undefined);
  assert.equal(first.descriptionHash, undefined);
  assert.equal(writes.length, 2);
  assert.equal(writes[0].id, first.analysisId);
  assert.equal(writes[0].value.userId, "qa_sender");
});

test("IRIS failures are bounded and never expose provider details", async () => {
  const server = createServer({
    dependenciesFactory: () => ({
      verifyIdToken: async () => ({uid: "qa_sender"}),
      verifyAppCheck: async () => ({}),
      handlers: {analyseIris: async () => {
        throw new Error("private provider detail");
      }},
    }),
    allowRequest: (() => {
      let remaining = 1;
      return () => {
        const allowed = remaining > 0;
        remaining -= 1;
        return allowed;
      };
    })(),
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
    const url = `http://127.0.0.1:${server.address().port}/analyseIris`;
    const headers = {"content-type": "application/json", authorization: "Bearer valid", "x-firebase-appcheck": "valid"};
    const providerError = await fetch(url, {method: "POST", headers, body: JSON.stringify({data: {description: "parcel"}})});
    assert.equal(providerError.status, 500);
    assert.doesNotMatch(JSON.stringify(await providerError.json()), /private provider detail/);
    const malformed = await fetch(url, {method: "POST", headers, body: "{malformed"});
    assert.equal(malformed.status, 500);
    assert.doesNotMatch(JSON.stringify(await malformed.json()), /SyntaxError/);
    const limited = await fetch(url, {method: "POST", headers, body: JSON.stringify({data: {description: "parcel"}})});
    assert.equal(limited.status, 429);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test("original photo SDK policy remains isolated from primary IRIS App Check and delegates to the same owner core", async () => {
  let calls = 0;
  const server = createServer({dependenciesFactory: () => ({verifyIdToken: async (token) => {
    if (token !== "valid") throw Object.assign(new Error("invalid"), {code: "auth/invalid-id-token"});
    return {uid: "test-owner"};
  }, verifyAppCheck: async () => {
throw Object.assign(new Error("invalid"), {code: "app-check/invalid-argument"});
}, handlers: {analyseParcelPhotoForIris: async (data, context) => {
    calls++;
    assert.equal(context.auth.uid, "test-owner");
    assert.equal(data.photoBase64, "opaque-test-bytes");
    return {serverAuthored: true};
  }}})});
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
    const base = `http://127.0.0.1:${server.address().port}`;
    const call = (name, auth, app) => fetch(`${base}/${name}`, {method: "POST", headers: {"content-type": "application/json", ...(auth ? {authorization: `Bearer ${auth}`} : {}), ...(app ? {"x-firebase-appcheck": app} : {})}, body: JSON.stringify({data: {photoBase64: "opaque-test-bytes"}})});
    assert.equal((await call("analyseParcelPhotoForIrisLegacy", null, null)).status, 401);
    assert.equal((await call("analyseParcelPhotoForIris", "valid", null)).status, 400);
    assert.equal((await call("analyseParcelPhotoForIrisLegacy", "invalid", null)).status, 401);
    assert.equal((await call("analyseParcelPhotoForIrisLegacy", "valid", "invalid")).status, 401);
    assert.equal(calls, 0);
    const response = await call("analyseParcelPhotoForIrisLegacy", "valid", null);
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {result: {serverAuthored: true}});
    assert.equal(calls, 1);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});
