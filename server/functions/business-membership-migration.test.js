"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const migration = require("./business-membership-migration")._private;

test("legacy Business members map to deterministic bounded records", () => {
  const members = migration.legacyMembers({
    ownerUid: "owner-1",
    contactEmail: "owner@example.com",
    teamMembers: [{userId: "member-1", email: "m@example.com", role: "finance", status: "active"}],
  });
  assert.equal(members.length, 2);
  assert.equal(migration.membershipId("business-1", members[0]), "business-1_member-1");
  assert.equal(migration.membershipId("business-1", members[1]), "business-1_owner-1");
});

test("email-only invitations receive stable non-plaintext membership IDs", () => {
  const id = migration.membershipId("business-1", {email: "Invite@Example.com"});
  assert.match(id, /^business-1_invite_[a-f0-9]{32}$/);
  assert.doesNotMatch(id, /example/);
});

test("production Business mutations no longer maintain membership arrays", () => {
  for (const file of ["business-access.js", "business-custom-roles.js", "admin-operations-authority.js"]) {
    const source = fs.readFileSync(file, "utf8");
    assert.doesNotMatch(source, /teamMemberIds|managerIds/);
    if (file !== "business-access.js") assert.doesNotMatch(source, /teamMembers/);
  }
  const access = fs.readFileSync("business-access.js", "utf8");
  assert.doesNotMatch(access, /account\.teamMembers|business\.teamMembers/);
  assert.match(access, /businessMemberships/);
  const website = fs.readFileSync(path.join(__dirname, "../../lib/website/shared/circum_website_app.dart"), "utf8");
  assert.doesNotMatch(website, /where\('teamMemberIds'/);
  assert.match(website, /httpsCallable\('listBusinessAccounts'\)/);
});
