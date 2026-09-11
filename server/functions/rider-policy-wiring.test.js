"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const read = (name) => fs.readFileSync(path.join(__dirname, name), "utf8");

test("only authoritative Admin Rider and closure operations enqueue policy work", () => {
  const admin = read("admin-rider-authority.js");
  const closure = read("account-closure.js");
  const presence = read("rider-presence.js");
  assert.match(admin, /enqueueRiderPolicyRecompute/);
  assert.match(closure, /enqueueRiderPolicyRecompute/);
  assert.doesNotMatch(presence, /enqueueRiderPolicyRecompute/);
});

test("Admin suspension writes canonical terminal policy before enqueue", () => {
  const source = read("admin-rider-authority.js");
  assert.match(source, /accountStatus: "suspended"/);
  assert.match(source, /riderStatus: "suspended"/);
  assert.match(source, /isSuspended: true/);
  assert.match(source, /accountStatus: "active"/);
  assert.match(source, /isSuspended: false/);
});

test("old and failed Gen 1 Rider policy triggers remain unexported", () => {
  const index = read("index.js");
  assert.doesNotMatch(index, /exports\.onRiderProfileAvailabilityWrite/);
  assert.doesNotMatch(index, /exports\.onRiderRecordAvailabilityWrite/);
  assert.doesNotMatch(index, /exports\.onRiderOperationalPolicyWrite/);
});
