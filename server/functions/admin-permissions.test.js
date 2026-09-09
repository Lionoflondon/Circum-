const test = require("node:test");
const assert = require("node:assert/strict");
const {
  normalizeRole,
  tokenRoles,
  hasPermission,
  permissionsForRoles,
  requireAppCheck,
} = require("./admin-permissions");

test("legacy Admin roles normalize without granting super-admin", () => {
  assert.equal(normalizeRole("admin"), "operations_admin");
  assert.equal(normalizeRole("customer_support"), "support_agent");
  assert.equal(normalizeRole("driver_manager"), "rider_reviewer");
  assert.deepEqual(tokenRoles({admin: true}), ["operations_admin"]);
  assert.deepEqual(tokenRoles({super_admin: true}), ["super_admin"]);
});

test("finance, support and Rider review remain least privilege", () => {
  assert.equal(hasPermission(["finance_admin"], "finance.manage"), true);
  assert.equal(hasPermission(["finance_admin"], "health.read"), false);
  assert.equal(hasPermission(["finance_admin"], "support.read"), false);
  assert.equal(hasPermission(["support_agent"], "support.manage"), true);
  assert.equal(hasPermission(["support_agent"], "finance.read"), false);
  assert.equal(hasPermission(["rider_reviewer"], "riders.review"), true);
  assert.equal(hasPermission(["rider_reviewer"], "payments.read"), false);
});

test("only explicit super-admin has wildcard permission", () => {
  assert.deepEqual(permissionsForRoles(["super_admin"]), ["*"]);
  assert.equal(hasPermission(["operations_admin"], "*"), false);
});

test("Admin App Check denies missing or invalid context and accepts verified context", () => {
  assert.throws(() => requireAppCheck({}), {code: "failed-precondition"});
  assert.throws(() => requireAppCheck({app: {}}), {code: "failed-precondition"});
  assert.equal(requireAppCheck({app: {appId: "admin-web-test"}}), "admin-web-test");
});
