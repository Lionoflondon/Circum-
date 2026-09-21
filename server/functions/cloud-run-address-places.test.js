"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {createHandlers, createRateLimiter, createServer, routeName} = require("./cloud-run-address-places");

async function listen(server, run) {
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
    await run(`http://127.0.0.1:${server.address().port}`);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

function dependencies(handlers) {
  return {
    verifyIdToken: async (token) => token === "valid-id" ? {uid: "sender-1"} : Promise.reject(Object.assign(new Error("bad auth"), {code: "auth/invalid-id-token"})),
    verifyAppCheck: async (token) => token === "valid-app" ? {appId: "circum-web"} : Promise.reject(Object.assign(new Error("bad app check"), {code: "app-check/invalid-argument"})),
    handlers,
  };
}

async function invoke(url, name, data, headers = {}) {
  return fetch(`${url}/${name}`, {
    method: "POST",
    headers: {"content-type": "application/json", authorization: "Bearer valid-id", "x-firebase-appcheck": "valid-app", ...headers},
    body: JSON.stringify({data}),
  });
}

test("legacy callable route names and v1 callable aliases are supported", () => {
  assert.equal(routeName("/searchFreeUkAddresses"), "searchFreeUkAddresses");
  assert.equal(routeName("/v1/callable/resolveUkAddressPlace"), "resolveUkAddressPlace");
  assert.equal(routeName("/unrelated"), null);
});

test("search and resolution preserve callable response shapes and UK restriction", async () => {
  const calls = [];
  const handlers = createHandlers({
    googlePlacesApiKey: "server-only-test-key",
    searchFreeUkAddresses: async (request) => {
      calls.push(["search", request]);
      return {status: "OK", results: [{displayAddress: "10 Downing Street, London, UK", placeId: "uk-place"}]};
    },
    resolveUkAddressPlace: async (request) => {
      calls.push(["resolve", request]);
      return {displayAddress: "10 Downing Street, London, UK", lat: 51.503, lng: -0.128, placeId: "uk-place", components: {country: "United Kingdom"}};
    },
  });
  const server = createServer({dependenciesFactory: () => dependencies(handlers)});
  await listen(server, async (url) => {
    let response = await invoke(url, "searchFreeUkAddresses", {query: " SW1A 2AA ", sessionToken: "session-1"});
    assert.equal(response.status, 200);
    assert.equal((await response.json()).result.results[0].placeId, "uk-place");
    response = await invoke(url, "resolveUkAddressPlace", {placeId: "uk-place", sessionToken: "session-1"});
    assert.equal(response.status, 200);
    assert.equal((await response.json()).result.components.country, "United Kingdom");
  });
  assert.equal(calls[0][1].googlePlacesApiKey, "server-only-test-key");
  assert.equal(calls[1][1].googlePlacesApiKey, "server-only-test-key");

  const foreign = createHandlers({googlePlacesApiKey: "server-only-test-key", resolveUkAddressPlace: async () => ({displayAddress: "Paris", lat: 48.8, lng: 2.3, components: {country: "France"}})});
  await assert.rejects(() => foreign.resolveUkAddressPlace({placeId: "foreign"}), (error) => error.code === "permission-denied");
});

test("transport rejects unauthenticated, missing App Check, malformed and over-limit requests", async () => {
  const handlers = createHandlers({googlePlacesApiKey: "server-only-test-key", searchFreeUkAddresses: async () => ({status: "OK", results: []})});
  const server = createServer({dependenciesFactory: () => dependencies(handlers), allowRequest: createRateLimiter({limit: 1, now: () => 1000})});
  await listen(server, async (url) => {
    let response = await fetch(`${url}/searchFreeUkAddresses`, {method: "POST", headers: {"content-type": "application/json"}, body: JSON.stringify({data: {query: "London"}})});
    assert.equal(response.status, 401);
    response = await invoke(url, "searchFreeUkAddresses", {query: "London"}, {"x-firebase-appcheck": ""});
    assert.equal(response.status, 400);
    response = await fetch(`${url}/searchFreeUkAddresses`, {method: "POST", headers: {"content-type": "application/json", authorization: "Bearer valid-id", "x-firebase-appcheck": "valid-app"}, body: JSON.stringify({unexpected: {}})});
    assert.equal(response.status, 400);
    response = await invoke(url, "searchFreeUkAddresses", {query: "London"});
    assert.equal(response.status, 200);
    response = await invoke(url, "searchFreeUkAddresses", {query: "Manchester"});
    assert.equal(response.status, 429);
  });
});

test("provider failures and missing secret are structured and secret-safe", async () => {
  let handlers = createHandlers({googlePlacesApiKey: "", searchFreeUkAddresses: async () => ({status: "OK", results: []})});
  await assert.rejects(() => handlers.searchFreeUkAddresses({query: "London"}), (error) => error.code === "failed-precondition" && !error.message.includes("key"));
  handlers = createHandlers({googlePlacesApiKey: "server-only-test-key", searchFreeUkAddresses: async () => {
    throw new Error("upstream included server-only-test-key");
  }});
  const server = createServer({dependenciesFactory: () => dependencies(handlers)});
  await listen(server, async (url) => {
    const response = await invoke(url, "searchFreeUkAddresses", {query: "London"});
    assert.equal(response.status, 503);
    const body = JSON.stringify(await response.json());
    assert.match(body, /UNAVAILABLE/);
    assert.doesNotMatch(body, /server-only-test-key/);
  });
});

test("health is dependency-free and reports exact source", async () => {
  const previous = process.env.CIRCUM_SOURCE_SHA;
  process.env.CIRCUM_SOURCE_SHA = "test-sha";
  const server = createServer({dependenciesFactory: () => {
    throw new Error("health must remain lazy");
  }});
  await listen(server, async (url) => {
    const response = await fetch(`${url}/health`);
    assert.equal(response.status, 200);
    const body = await response.json();
    assert.equal(body.source, "test-sha");
    assert.deepEqual(body.operations.sort(), ["resolveUkAddressPlace", "searchFreeUkAddresses"]);
  });
  if (previous === undefined) delete process.env.CIRCUM_SOURCE_SHA;
  else process.env.CIRCUM_SOURCE_SHA = previous;
});
