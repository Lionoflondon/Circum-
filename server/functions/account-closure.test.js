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
  assert.ok(accountClosure._test.ACTIVE_DELIVERY_STATUSES.includes("active"));
  assert.ok(accountClosure._test.ACTIVE_DELIVERY_STATUSES.includes("pending"));
});

test("sender account closure cleans owned Gift voice media", () => {
  assert.match(source, /cleanupGiftVoiceMediaForAccount/);
  assert.match(source, /accountType === "sender"/);
});

test("Sender closure remains recoverable until the client deletes Firebase Auth", () => {
  assert.match(source, /status: "ready_for_auth_deletion"/);
  assert.match(source, /idempotent: true/);
  assert.match(source, /idempotent: false/);
  assert.match(source, /if \(accountType === "rider"\)/);
  assert.match(source, /await getAuth\(\)\.deleteUser\(uid\)/);
});

test("account closure checks every Firestore status query chunk", () => {
  assert.match(source, /index < ACTIVE_DELIVERY_STATUSES\.length/);
  assert.match(source, /ACTIVE_DELIVERY_STATUSES\.slice\(index, index \+ 10\)/);
});
