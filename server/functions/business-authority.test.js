const test = require("node:test");
const assert = require("node:assert/strict");
const {businessAuthority, normalizedPermissions, hasBusinessPermission} = require("./business-authority");

test("Business owner and finance-capable roles may perform financial actions", () => {
  for (const role of ["owner", "admin", "manager", "finance"]) {
    assert.equal(businessAuthority({teamMembers: [{userId: "u", role, status: "active"}]}, {uid: "u"}).financialAuthorized, true);
  }
});

test("ordinary members cannot gain financial authority and legacy arrays grant no access", () => {
  assert.equal(businessAuthority({teamMembers: [{userId: "u", role: "member", status: "active"}]}, {uid: "u"}).financialAuthorized, false);
  const legacy = businessAuthority({teamMemberIds: ["u"]}, {uid: "u"});
  assert.equal(legacy.member, false);
  assert.equal(legacy.financialAuthorized, false);
});

test("removed or suspended canonical members fail closed", () => {
  assert.equal(businessAuthority({teamMembers: [{userId: "u", role: "finance", status: "removed"}]}, {uid: "u"}).member, false);
  assert.equal(businessAuthority({teamMembers: [{userId: "u", role: "finance", status: "suspended"}]}, {uid: "u"}).member, false);
});

test("mutation permissions are exact and unknown authority is discarded", () => {
  const permissions = normalizedPermissions([
    "deliveries.create", "deliveries.cancel", "deliveries.notes.modify",
    "team.invite", "team.remove", "team.roles.assign",
    "finance.payments.initiate", "operations.incidents.acknowledge",
    "platform.admin",
  ]);
  assert.equal(permissions.includes("platform.admin"), false);
  const authority = businessAuthority(
      {teamMembers: [{userId: "u", role: "custom", status: "active"}]},
      {uid: "u", customPermissions: permissions},
  );
  assert.equal(hasBusinessPermission(authority, "deliveries.create"), true);
  assert.equal(hasBusinessPermission(authority, "finance.roth.use"), false);
});
