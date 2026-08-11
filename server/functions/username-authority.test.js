"use strict";

const assert = require("assert");
const {test} = require("node:test");
const authority = require("./username-authority");

test("normalizes the public handle", () => {
  assert.deepEqual(authority._normalizeUsername("  @Ayo "), {
    normalized: "ayo",
    display: "Ayo",
  });
});

test("rejects invalid and reserved handles", () => {
  assert.throws(() => authority._normalizeUsername("ab"), /3 and 30/);
  assert.throws(() => authority._normalizeUsername("circum"), /reserved/);
  assert.throws(() => authority._normalizeUsername("ayo smith"), /letters/);
});
