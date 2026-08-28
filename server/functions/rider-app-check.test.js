"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const source = (file) => fs.readFileSync(path.join(__dirname, file), "utf8");

test("Rider operational callable wrapper enforces Firebase App Check", () => {
  const wrapper = source("rider-app-check.js");
  assert.match(wrapper, /runWith\(\{enforceAppCheck:\s*true\}\)\.https\.onCall\(handler\)/);
  assert.doesNotMatch(wrapper, /https\.onCall\(\{enforceAppCheck:/);
});

test("Rider operational callables use the App Check wrapper", () => {
  for (const file of [
    "rider-presence.js",
    "get-avaliable-requests.js",
    "accept-ride-requests.js",
    "delivery-tracking.js",
    "rider-account.js",
  ]) {
    const text = source(file);
    assert.match(text, /require\("\.\/rider-app-check"\)/, file);
    assert.match(text, /riderCallable\(/, file);
  }
});
