"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {_planLegacyRows: plan, _candidateRowsForUser: candidates} = require("./username-migration");

test("legacy aliases consolidate for one UID and normalize deterministically", () => {
  const rows = candidates("uid-a", {
    users: {username: "@Ayo"},
    riders: {handle: " ayo "},
    riderProfiles: {username: "AYO"},
  });
  const result = [...plan(rows).values()][0];
  assert.equal(result.status, "MIGRATED");
  assert.equal(result.normalizedHandle, "ayo");
  assert.equal(result.sources.length, 3);
});

test("cross-UID legacy collision fails closed with only migration metadata", () => {
  const result = [...plan([
    {uid: "uid-a", source: "users.username", raw: "@jason"},
    {uid: "uid-b", source: "riders.handle", raw: "JASON"},
  ]).values()];
  assert.equal(result.length, 2);
  assert.ok(result.every((item) => item.status === "COLLISION_REVIEW_REQUIRED"));
  assert.deepEqual(result.map((item) => item.uid).sort(), ["uid-a", "uid-b"]);
  assert.ok(result.every((item) => !Object.hasOwn(item, "email")));
});

test("invalid and missing legacy handles are classified fail-closed", () => {
  const invalid = [...plan([{uid: "uid-a", source: "users.username", raw: "bad name"}]).values()][0];
  const missing = [...plan(candidates("uid-b", {users: {}, riders: {}, riderProfiles: {}})).values()][0];
  assert.equal(invalid.status, "INVALID_LEGACY_HANDLE");
  assert.equal(missing.status, "MISSING_HANDLE");
});

test("existing registry ownership is already canonical or a collision", () => {
  const canonical = [...plan([{uid: "uid-a", source: "users.username", raw: "@Ayo"}],
    new Map([["ayo", {uid: "uid-a"}]]),
  ).values()][0];
  const conflict = [...plan([{uid: "uid-a", source: "users.username", raw: "@Ayo"}],
    new Map([["ayo", {uid: "uid-b"}]]),
  ).values()][0];
  assert.equal(canonical.status, "ALREADY_CANONICAL");
  assert.equal(conflict.status, "COLLISION_REVIEW_REQUIRED");
});
