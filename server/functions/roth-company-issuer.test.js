"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {isAuthorizedCircumIssuer, isValidStagingRewardAmount, MAX_STAGING_REWARD_PENCE} = require("./roth-company-issuer");

test("active tenant-local CIRCUM administrator may issue rewards", () => {
  assert.equal(isAuthorizedCircumIssuer({status: "active", role: "admin"}), true);
  assert.equal(isAuthorizedCircumIssuer({status: "active", roles: ["finance_admin"]}), true);
});

test("issuer approval requires active company-side record, not token claims", () => {
  assert.equal(isAuthorizedCircumIssuer(null), false);
  assert.equal(isAuthorizedCircumIssuer({role: "admin", status: "inactive"}), false);
  assert.equal(isAuthorizedCircumIssuer({role: "admin"}), false);
});

test("explicit company scope rejects an administrator from another company", () => {
  assert.equal(isAuthorizedCircumIssuer({status: "active", role: "admin", companyId: "PARKPAL"}), false);
  assert.equal(isAuthorizedCircumIssuer({status: "active", role: "admin", tenantId: "CORPVS CHRISTI"}), false);
});

test("staging reward amounts are bounded by the approved ten pound maximum", () => {
  assert.equal(MAX_STAGING_REWARD_PENCE, 1000);
  assert.equal(isValidStagingRewardAmount(1), true);
  assert.equal(isValidStagingRewardAmount(1000), true);
  assert.equal(isValidStagingRewardAmount(1001), false);
  assert.equal(isValidStagingRewardAmount(0), false);
  assert.equal(isValidStagingRewardAmount(1.2), false);
  assert.equal(isValidStagingRewardAmount(Number.MAX_SAFE_INTEGER + 1), false);
});
