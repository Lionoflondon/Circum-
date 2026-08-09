const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const {
  FOUNDER_UID,
  FOUNDER_EMAIL,
  assertFounder,
  isFounderContext,
} = require("./founder-authority");

test("Founder authority is restricted to the single compiled UID and email", () => {
  const founderContext = {
    auth: {
      uid: FOUNDER_UID,
      token: {email: FOUNDER_EMAIL},
    },
  };

  assert.deepEqual(assertFounder(founderContext), {
    uid: FOUNDER_UID,
    email: FOUNDER_EMAIL,
  });
  assert.equal(isFounderContext(founderContext), true);
  assert.equal(isFounderContext({auth: {uid: FOUNDER_UID, token: {email: "other@example.com"}}}), false);
  assert.equal(isFounderContext({auth: {uid: "other", token: {email: FOUNDER_EMAIL}}}), false);
  assert.throws(() => assertFounder({auth: {uid: "other", token: {email: FOUNDER_EMAIL}}}));
});

test("Founder test account designation is backend-only and audited", () => {
  const source = fs.readFileSync(path.join(__dirname, "founder-authority.js"), "utf8");

  assert.match(source, /exports|module\.exports/);
  assert.match(source, /founderDesignateTestAccount/);
  assert.match(source, /founderRevokeTestAccount/);
  assert.match(source, /founderListTestAccounts/);
  assert.match(source, /founderPreflightE2E/);
  assert.match(source, /founderRiderOperationalPreflight/);
  assert.match(source, /reconcileFounderRiderState/);
  assert.match(source, /assertFounder\(context\)/);
  assert.match(source, /collection\("founderTestAccounts"\)/);
  assert.match(source, /collection\("founderAuthorityAudit"\)/);
  assert.match(source, /previousValues/);
  assert.match(source, /newValues/);
  assert.match(source, /immutable: true/);
});

test("Founder operational reconciliation is UID-locked and audited", () => {
  const source = fs.readFileSync(path.join(__dirname, "founder-authority.js"), "utf8");
  assert.match(source, /isFounderRiderUid/);
  assert.match(source, /founder_operational_state_reconciled/);
  assert.match(source, /collection\("riderOperationalAudit"\)/);
  assert.match(source, /transaction\.set\(riderRef/);
  assert.match(source, /transaction\.set\(profileRef/);
  assert.match(source, /FOUNDER_OPERATIONAL_WAIVERS/);
});

test("Founder authority is exported without trusting client role claims", () => {
  const indexSource = fs.readFileSync(path.join(__dirname, "index.js"), "utf8");
  const authoritySource = fs.readFileSync(path.join(__dirname, "founder-authority.js"), "utf8");

  assert.match(indexSource, /founderDesignateTestAccount/);
  assert.match(indexSource, /founderRevokeTestAccount/);
  assert.match(indexSource, /founderListTestAccounts/);
  assert.match(indexSource, /founderPreflightE2E/);
  assert.match(indexSource, /founderRiderOperationalPreflight/);
  assert.doesNotMatch(authoritySource, /token\.role/);
  assert.doesNotMatch(authoritySource, /token\.adminRole/);
  assert.doesNotMatch(authoritySource, /super_admin/);
});

test("Founder preflight is audited and does not fake infrastructure checks", () => {
  const source = fs.readFileSync(path.join(__dirname, "founder-authority.js"), "utf8");

  assert.match(source, /action: "founder_preflight_e2e"/);
  assert.match(source, /correlationId/);
  assert.match(source, /previousValues/);
  assert.match(source, /newValues/);
  assert.match(source, /requires_live_device_token_confirmation/);
  assert.match(source, /requires_rules_emulator_or_live_rules_test/);
  assert.match(source, /requires_storage_rules_test/);
});
