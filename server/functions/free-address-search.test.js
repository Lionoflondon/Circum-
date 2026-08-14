/* eslint-disable max-len, require-jsdoc */
const test = require("node:test");
const assert = require("node:assert/strict");
const {
  _searchFreeUkAddressesHandler: search,
  _resolveUkAddressPlaceHandler: resolve,
} = require("./free-address-search");

function fakeDb() {
  const values = new Map();
  return {
    collection: () => ({
      doc: (key) => ({key}),
    }),
    runTransaction: async (callback) => callback({
      get: async (ref) => ({exists: values.has(ref.key), data: () => values.get(ref.key)}),
      set: (ref, value) => values.set(ref.key, {...(values.get(ref.key) || {}), ...value}),
    }),
  };
}

const auth = {auth: {uid: "user-1"}};

test("address callables reject unauthenticated requests", async () => {
  await assert.rejects(() => search({query: "London"}, {}), {code: "unauthenticated"});
  await assert.rejects(() => resolve({placeId: "place-1"}, {}), {code: "unauthenticated"});
});

test("authenticated address search preserves response shape", async () => {
  const result = await search({query: "London", sessionToken: "token-1"}, auth, {
    db: fakeDb(),
    searchImpl: async ({query, sessionToken}) => ({status: "OK", results: [{query, sessionToken}]}),
  });
  assert.deepEqual(result, {
    status: "OK",
    results: [{query: "London", sessionToken: "token-1"}],
  });
});

test("address validation rejects empty, oversized and malformed values", async () => {
  await assert.rejects(() => search({}, auth, {db: fakeDb()}), {code: "invalid-argument"});
  await assert.rejects(() => search({query: "x".repeat(161)}, auth, {db: fakeDb()}), {code: "invalid-argument"});
  await assert.rejects(() => search({query: "London", sessionToken: "bad token"}, auth, {db: fakeDb()}), {code: "invalid-argument"});
  await assert.rejects(() => resolve({placeId: ""}, auth, {db: fakeDb()}), {code: "invalid-argument"});
  await assert.rejects(() => resolve({placeId: "place/1"}, auth, {db: fakeDb()}), {code: "invalid-argument"});
});

test("address rate limit allows twenty requests and rejects the next", async () => {
  const db = fakeDb();
  const options = {db, searchImpl: async () => ({status: "OK", results: []})};
  for (let i = 0; i < 20; i++) await search({query: "London"}, auth, options);
  await assert.rejects(() => search({query: "London"}, auth, options), {code: "resource-exhausted"});
});

test("address rate limit resets after its window", async () => {
  const {checkAndConsumeRateLimit} = require("./rate-limit-core");
  const db = fakeDb();
  assert.equal((await checkAndConsumeRateLimit({db, key: "reset", max: 1, windowSeconds: 60, nowMs: 0})).allowed, true);
  assert.equal((await checkAndConsumeRateLimit({db, key: "reset", max: 1, windowSeconds: 60, nowMs: 60000})).allowed, true);
});
