"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {createEnsureSenderAccountCompat} = require("./account-bootstrap-compat");

const context = {
  auth: {uid: "sender-1"},
  rawRequest: {headers: {authorization: "Bearer firebase-id-token"}},
};

test("ensureSenderAccount compatibility callable forwards auth and callable data", async () => {
  let request;
  const call = createEnsureSenderAccountCompat({
    endpoint: "https://account.example/ensureSenderAccount",
    fetchImpl: async (url, options) => {
      request = {url, options};
      return {ok: true, json: async () => ({result: {ok: true, action: "existing_sender_role_allowed"}})};
    },
  });

  const result = await call({source: "legacy-client"}, context);

  assert.deepEqual(result, {ok: true, action: "existing_sender_role_allowed"});
  assert.equal(request.url, "https://account.example/ensureSenderAccount");
  assert.equal(request.options.method, "POST");
  assert.equal(request.options.headers.authorization, "Bearer firebase-id-token");
  assert.equal(request.options.headers["content-type"], "application/json");
  assert.deepEqual(JSON.parse(request.options.body), {data: {source: "legacy-client"}});
});

test("ensureSenderAccount compatibility callable rejects unauthenticated requests before forwarding", async () => {
  let forwarded = false;
  const call = createEnsureSenderAccountCompat({
    fetchImpl: async () => {
      forwarded = true;
      return {ok: true, json: async () => ({result: {ok: true}})};
    },
  });

  await assert.rejects(call({}, {rawRequest: {headers: {}}}), /Sign in to continue/);
  assert.equal(forwarded, false);
});

test("ensureSenderAccount compatibility callable maps Cloud Run errors to callable errors", async () => {
  const call = createEnsureSenderAccountCompat({
    fetchImpl: async () => ({
      ok: false,
      status: 403,
      json: async () => ({error: {status: "PERMISSION_DENIED", message: "Sender account required."}}),
    }),
  });

  await assert.rejects(call({}, context), (error) => {
    assert.match(error.code, /permission-denied$/);
    assert.equal(error.message, "Sender account required.");
    return true;
  });
});

test("ensureSenderAccount compatibility callable reports Cloud Run transport failures as unavailable", async () => {
  const call = createEnsureSenderAccountCompat({fetchImpl: async () => {
    throw new Error("upstream unavailable");
  }});

  await assert.rejects(call({}, context), (error) => {
    assert.match(error.code, /unavailable$/);
    return true;
  });
});
