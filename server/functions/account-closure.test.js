const test = require("node:test");
const assert = require("node:assert/strict");

const accountClosure = require("./account-closure");

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
