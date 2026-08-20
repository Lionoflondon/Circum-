const assert = require("node:assert/strict");
const childProcess = require("node:child_process");
const path = require("node:path");
const test = require("node:test");

const root = path.resolve(__dirname, "..");
const script = path.join(__dirname, "scoped_functions_deploy_list.js");

function scope(files) {
  return childProcess.execFileSync(process.execPath, [script, "--files", files.join(","), "--names"], {
    cwd: root,
    encoding: "utf8",
  }).trim().split(/\r?\n/).filter(Boolean);
}

test("shared state core includes only genuine dependent exports", () => {
  const names = scope(["server/functions/sender-tracking-state-core.js"]);
  assert.deepEqual(names, ["updateDeliveryTrackingStatus", "updateDeliveryLiveLocation"]);
  assert.equal(names.includes("getSenderGiftStory"), false);
});

test("Gift Story module retains its 18-function scope", () => {
  assert.equal(scope(["server/functions/gift-story-automation.js"]).length, 18);
});

test("UI-only input has no Functions", () => {
  assert.deepEqual(scope(["lib/app/sender_mobile/sender_mobile_home.dart"]), []);
});

test("unmapped backend input fails closed", () => {
  assert.throws(() => scope(["server/functions/package.json"]), /Backend changes|Dynamic require/);
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
