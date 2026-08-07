const assert = require("node:assert/strict");
const test = require("node:test");
const {
  BUSINESS_ROTH_POLICY,
  evaluateBusinessRothPurchase,
  parseGbpPence,
} = require("./business-roth-policy");

function account(role = "owner", limit = BUSINESS_ROTH_POLICY.maxSinglePurchasePence) {
  return {
    ownerUid: role === "owner" ? "user-1" : "owner-1",
    rothPurchaseLimitPence: limit,
    permissions: {admin: ["finance"]},
    teamMembers: [{userId: "user-1", role, status: "active"}],
  };
}

test("Business Roth parses exact GBP pence without floating point drift", () => {
  for (const [input, expected] of [
    ["1", 100],
    ["1.00", 100],
    ["10000", 1000000],
    ["50,000", 5000000],
    ["50000.00", 5000000],
    ["1000000", 100000000],
    ["1,000,000", 100000000],
    ["1000000.00", 100000000],
  ]) assert.equal(parseGbpPence(input), expected);
  assert.equal(parseGbpPence("1,000,000.00"), 100000000);
  assert.equal(parseGbpPence("50000"), 5000000);
  assert.equal(parseGbpPence("1.001"), null);
  assert.equal(parseGbpPence("Infinity"), null);
});

test("one million pounds is permitted only for financial authority", () => {
  const allowed = evaluateBusinessRothPurchase({
    account: account("owner"), uid: "user-1", amountPence: 100000000,
  });
  const member = evaluateBusinessRothPurchase({
    account: account("member"), uid: "user-1", amountPence: 100000000,
  });
  assert.equal(allowed.allowed, true);
  assert.equal(allowed.tier, "high_value");
  assert.equal(member.allowed, false);
});

test("owner-authorized financial team members can purchase without a second approver", () => {
  const authorized = account("finance");
  const result = evaluateBusinessRothPurchase({
    account: authorized,
    uid: "user-1",
    amountPence: 100000000,
  });
  assert.equal(result.allowed, true);
  assert.equal(result.confirmationRequired, true);
});

test("platform and Business limits are enforced at exact boundaries", () => {
  const owner = account("owner");
  assert.equal(evaluateBusinessRothPurchase({account: owner, uid: "user-1", amountPence: 100000000}).allowed, true);
  assert.equal(evaluateBusinessRothPurchase({account: owner, uid: "user-1", amountPence: 100000001}).allowed, false);
  assert.equal(evaluateBusinessRothPurchase({account: account("owner", 50000000), uid: "user-1", amountPence: 50000001}).allowed, false);
});

test("administrators inherit financial authority only from canonical permissions", () => {
  assert.equal(evaluateBusinessRothPurchase({account: account("admin"), uid: "user-1", amountPence: 100000000}).allowed, true);
  const adminWithoutFinance = account("admin");
  adminWithoutFinance.permissions = {admin: ["deliveries"]};
  assert.equal(evaluateBusinessRothPurchase({account: adminWithoutFinance, uid: "user-1", amountPence: 100000000}).allowed, false);
});
