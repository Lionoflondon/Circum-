/* eslint-disable max-len */
/* eslint-disable require-jsdoc */
const test = require("node:test");
const assert = require("node:assert/strict");
const {hasAdminClaim, requireAdmin} = require("./admin-auth");

function context(token, uid = "actor-uid") {
  return {auth: {uid, token}};
}

test("admin callable guard rejects unauthenticated callers", () => {
  assert.throws(
      () => requireAdmin({}),
      (error) => error.code === "unauthenticated",
  );
});

test("admin callable guard rejects ordinary and unrelated roles", () => {
  for (const token of [
    {},
    {role: "sender"},
    {role: "rider"},
    {roles: ["sender", "rider"]},
    {adminRole: "support_agent"},
  ]) {
    assert.equal(hasAdminClaim(token), false);
    assert.throws(
        () => requireAdmin(context(token)),
        (error) => error.code === "permission-denied",
    );
  }
});

test("admin callable guard accepts established admin claim shapes", () => {
  for (const token of [
    {admin: true},
    {superAdmin: true},
    {super_admin: true},
    {adminRole: "admin"},
    {role: "super_admin"},
    {roles: ["operations_admin"]},
    {roles: ["sender", "ADMIN"]},
  ]) {
    assert.equal(hasAdminClaim(token), true);
    assert.equal(requireAdmin(context(token, "admin-123")), "admin-123");
  }
});
