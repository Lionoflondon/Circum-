"use strict";

const assert = require("node:assert/strict");
const {execFileSync} = require("node:child_process");
const path = require("node:path");
const test = require("node:test");

const root = path.join(__dirname, "..", "..");

function names(args) {
  const output = execFileSync(process.execPath, [
    path.join(root, "scripts/scoped_functions_deploy_list.js"), ...args, "--names",
  ], {cwd: root, encoding: "utf8"});
  return output.trim() ? output.trim().split(/\r?\n/) : [];
}

test("Gift Story module changes deploy only Gift Story exports", () => {
  const result = names(["--files", "server/functions/gift-story-automation.js"]);
  assert.ok(result.includes("getSenderGiftStory"));
  assert.ok(result.includes("onGiftDeliveryCompleted"));
  assert.ok(!result.includes("createSenderPaidDelivery"));
  assert.ok(result.length < 252);
});

test("a UI-only change produces no Functions deployment", () => {
  assert.deepEqual(names(["--files", "lib/app/sender_mobile/sender_mobile_profile.dart"]), []);
});

test("no backend diff produces no Functions deployment", () => {
  assert.deepEqual(names([]), []);
});
