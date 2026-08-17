"use strict";

const assert = require("node:assert/strict");
const {execFileSync} = require("node:child_process");
const test = require("node:test");

function names(base) {
  const output = execFileSync(process.execPath, [
    "scripts/scoped_functions_deploy_list.js", "--base", base, "--names",
  ], {encoding: "utf8"});
  return output.trim() ? output.trim().split(/\r?\n/) : [];
}

test("Gift Story module changes deploy only Gift Story exports", () => {
  const result = names("ad8bd8056ad59bccdaa452ef6670369ac5ef567f");
  assert.ok(result.includes("getSenderGiftStory"));
  assert.ok(result.includes("onGiftDeliveryCompleted"));
  assert.ok(!result.includes("createSenderPaidDelivery"));
  assert.ok(result.length < 252);
});

test("a UI-only change produces no Functions deployment", () => {
  assert.deepEqual(names("a46582ef6910f9fa198766cded0ba65bf5aa15c9"), []);
});

test("no backend diff produces no Functions deployment", () => {
  assert.deepEqual(names("42004fd111158cb5a3b171ee2ed24f29e0afb2aa"), []);
});
