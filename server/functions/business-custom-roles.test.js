"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const {roleRecord} = require("./business-custom-roles")._private;

test("custom role records retain only server-approved granular permissions", () => {
  const role = roleRecord({name: "Warehouse Manager", description: "Pickup team", permissions: [
    "deliveries.view", "deliveries.status", "platform.admin", "other_business.read",
  ]}, "business-1", "owner-1");
  assert.deepEqual(role.permissions, ["deliveries.status", "deliveries.view"]);
  assert.equal(role.businessId, "business-1");
});

test("custom role definitions are owner-only and assignments prevent escalation", () => {
  const source = fs.readFileSync("business-custom-roles.js", "utf8");
  assert.match(source, /role !== "owner"/);
  assert.match(source, /businessAuditLogs/);
  for (const action of ["business_custom_role_created", "business_custom_role_updated", "business_custom_role_removed", "business_custom_role_assigned"]) assert.match(source, new RegExp(action));
  assert.match(source, /previousPermissions/);
  assert.match(source, /newPermissions/);
  assert.match(source, /team\.roles\.assign/);
  assert.match(source, /cannot grant permissions it does not hold/);
  assert.match(source, /Business administrators cannot be replaced/);
});

test("assigned custom roles remain scoped to the member business", () => {
  const source = fs.readFileSync("business-custom-roles.js", "utf8");
  assert.match(source, /text\(role\.data\(\)\.businessId\) !== businessId/);
  assert.match(source, /role: "custom", customRoleId: roleId/);
});
