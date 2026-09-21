const assert = require("node:assert/strict");
const childProcess = require("node:child_process");
const path = require("node:path");
const test = require("node:test");

const root = path.resolve(__dirname, "..");
const script = path.join(__dirname, "scoped_functions_deploy_list.js");
const scopeValidator = path.join(__dirname, "validate_functions_deploy_scope.js");

function scope(files) {
  return childProcess.execFileSync(process.execPath, [script, "--files", files.join(","), "--names"], {
    cwd: root,
    encoding: "utf8",
  }).trim().split(/\r?\n/).filter(Boolean);
}

test("shared state core includes its genuine dependent exports", () => {
  const names = scope(["server/functions/sender-tracking-state-core.js"]);
  assert.equal(names.includes("updateDeliveryTrackingStatus"), true);
  assert.equal(names.includes("updateDeliveryLiveLocation"), true);
  assert.equal(names.includes("reconcilePendingDeliverySettlements"), true);
  assert.equal(names.includes("getSenderGiftStory"), false);
});

test("Gift Story module includes direct and transitive owners without broadening globally", () => {
  const names = scope(["server/functions/gift-story-automation.js"]);
  assert.equal(names.includes("getSenderGiftStory"), true);
  assert.equal(names.includes("onGiftDeliveryCompleted"), true);
  assert.equal(names.includes("createSenderPaidDelivery"), false);
});

test("UI-only input has no Functions", () => {
  assert.deepEqual(scope(["lib/app/sender_mobile/sender_mobile_home.dart"]), []);
});

test("runtime declaration changes include every exported Function", () => {
  const names = scope(["server/functions/package.json"]);
  assert.ok(names.length > 0);
  assert.equal(names.includes("submitRiderApplication"), true);
  assert.equal(names.includes("updateRiderProfile"), false);
});

test("cycle traversal is finite and deduplicated", () => {
  const names = scope(["server/functions/sender-tracking-state-core.js"]);
  assert.equal(new Set(names).size, names.length);
});

test("direct module aliases are included in the deployment scope", () => {
  const names = scope([
    "server/functions/get-avaliable-requests.js",
    "server/functions/accept-ride-requests.js",
  ]);
  assert.equal(names.includes("getAvailableRequests"), true);
  assert.equal(names.includes("acceptRideRequests"), true);
});

test("manual retry scope accepts only known exported Functions", () => {
  const output = childProcess.execFileSync(process.execPath, [
    scopeValidator,
    "functions:goOnline,functions:goOffline",
  ], {cwd: root, encoding: "utf8"});
  assert.equal(output, "functions:goOnline,functions:goOffline");
});

test("manual retry scope rejects unknown or unscoped targets", () => {
  assert.throws(() => childProcess.execFileSync(process.execPath, [
    scopeValidator,
    "functions:notAnExport",
  ], {cwd: root, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"]}));
  assert.throws(() => childProcess.execFileSync(process.execPath, [
    scopeValidator,
    "functions:goOnline,functions:goOnline",
  ], {cwd: root, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"]}));
});
