/* eslint-disable max-len */
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const accountClosure = require("./account-closure");
const source = fs.readFileSync(path.join(__dirname, "account-closure.js"), "utf8");

test("account closure exposes one shared callable for sender and rider", () => {
  assert.equal(typeof accountClosure.closeAccount, "function");
});

test("rider operational blocker uses canonical account closure copy", () => {
  assert.equal(
      accountClosure._test.blockerMessage("rider", "active_delivery"),
      "Your account cannot be closed while operational activity is still in progress.",
  );
});

test("active delivery states include accepted delivery lifecycle", () => {
  assert.ok(accountClosure._test.ACTIVE_DELIVERY_STATUSES.includes("accepted"));
  assert.ok(accountClosure._test.ACTIVE_DELIVERY_STATUSES.includes("awaiting_pin"));
});

test("sender account closure cleans owned Gift voice media", () => {
  assert.match(source, /cleanupGiftVoiceMediaForAccount/);
  assert.match(source, /accountType === "sender"/);
});

test("account closure retains handle ownership while removing profile presentation", () => {
  assert.match(source, /collection\("usernames"\)\.doc\(retainedUsername\)/);
  assert.match(source, /retainedReason: "account_closed"/);
  assert.match(source, /username: FieldValue\.delete\(\)/);
  assert.match(source, /usernameUpdatedAt: FieldValue\.delete\(\)/);
});
