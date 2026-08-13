"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");
const {spawnSync} = require("node:child_process");

const script = path.resolve(__dirname, "scoped_functions_deploy_list.js");

function run(...args) {
  return spawnSync(process.execPath, [script, ...args], {encoding: "utf8"});
}

test("--only emits exactly the requested deduplicated Functions scope", () => {
  const result = run(
      "--only",
      "createGiftPayment,finalizeGiftPayment,createGiftPayment",
  );
  assert.equal(result.status, 0, result.stderr);
  assert.equal(
      result.stdout.trim(),
      "functions:createGiftPayment,functions:finalizeGiftPayment",
  );
});

test("--only rejects empty scope instead of falling back to all Functions", () => {
  const result = run("--only", "");
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /requires at least one/);
  assert.equal(result.stdout, "");
});

test("--only rejects names that are not exported", () => {
  const result = run("--only=notARealCircumFunction");
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /Unknown function exports/);
  assert.equal(result.stdout, "");
});
