const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {LIMITS, WINDOW_MS} = require("./iris-request-guard");

test("IRIS runaway protection allows legitimate interactive bursts", () => {
  assert.equal(WINDOW_MS, 10 * 60 * 1000);
  assert.ok(LIMITS.analyse_iris >= 100);
  assert.ok(LIMITS.analyse_iris_photo >= 20);
  assert.ok(LIMITS.report_load_discrepancy >= 10);
});

test("IRIS rate limits are user and endpoint scoped and transaction backed", () => {
  const source = fs.readFileSync(path.join(__dirname, "iris-request-guard.js"), "utf8");
  assert.match(source, /safeId\(uid\)/);
  assert.match(source, /_\$\{action\}_\$\{bucket\}/);
  assert.match(source, /db\.runTransaction/);
  assert.match(source, /resource-exhausted/);
});
