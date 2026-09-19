"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {tokenHash, normalizeRole, PROFILE_COLLECTIONS, TOKEN_FIELDS} = require("./device-token-authority");

test("token authority uses deterministic non-plaintext document identifiers", () => {
  const token = "physical-device-token";
  assert.equal(tokenHash(token), tokenHash(token));
  assert.equal(tokenHash(token).length, 64);
  assert.notEqual(tokenHash(token), token);
});

test("token authority normalizes only sender and rider roles", () => {
  assert.equal(normalizeRole("shipper"), "sender");
  assert.equal(normalizeRole("driver"), "rider");
  assert.throws(() => normalizeRole("admin"));
});

test("registration audits every legacy profile and token field", () => {
  assert.deepEqual(PROFILE_COLLECTIONS, ["users", "senders", "riderProfiles", "riders"]);
  assert.deepEqual(TOKEN_FIELDS, ["fcmToken", "pushToken", "code"]);
});
