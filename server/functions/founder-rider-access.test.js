"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const access = require("./founder-rider-access");

test("only intended UID can receive override", () => {
  assert.doesNotThrow(
      () => access.assertFounderTarget(access.FOUNDER_RIDER_UID),
  );
  assert.throws(() => access.assertFounderTarget("other"));
});

test("personal Founder projection uses founder recognition, not the Founding Rider cohort", () => {
  const source = fs.readFileSync(path.join(__dirname, "founder-rider-access.js"), "utf8");
  assert.match(source, /founderRecognition:\s*"founder"/);
  assert.match(source, /recognitions:\s*\{[\s\S]*founder:/);
  assert.doesNotMatch(source, /foundingRider/);
});
