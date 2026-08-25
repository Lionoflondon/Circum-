"use strict";

const assert = require("assert");
const {test} = require("node:test");
const fs = require("fs");
const path = require("path");
const {definitionHash, isEligibleUser, reconcileGrantRecords, MAX_ROTH_PER_USER, MAX_CAMPAIGN_ROTH, MAX_INDIVIDUAL_ROTH} = require("./roth-grant-campaigns");

const definition = {
  name: "Welcome gift",
  rothPerUser: 10,
  recipientScope: "active_customers",
  eligibilityRules: {},
  uidAllowlist: [],
  uidExclusionList: [],
};

test("campaign eligibility excludes privileged, closed, suspended, test and deleted accounts", () => {
  assert.equal(isEligibleUser("customer", {role: "customer"}, definition).eligible, true);
  for (const user of [
    {role: "rider"}, {role: "admin"}, {isInternal: true}, {isTestAccount: true},
    {closed: true}, {deleted: true}, {suspended: true}, {accountStatus: "fraud_blocked"},
  ]) assert.equal(isEligibleUser("excluded", user, definition).eligible, false);
});

test("allow and exclusion lists are server-side eligibility rules", () => {
  const scoped = {...definition, uidAllowlist: ["allowed"], uidExclusionList: ["excluded"]};
  assert.equal(isEligibleUser("allowed", {}, scoped).eligible, true);
  assert.equal(isEligibleUser("other", {}, scoped).reason, "not_in_allowlist");
  assert.equal(isEligibleUser("excluded", {}, {...definition, uidExclusionList: ["excluded"]}).reason, "explicitly_excluded");
});

test("campaign definition hashes are deterministic and safety caps are finite", () => {
  assert.equal(definitionHash(definition), definitionHash({...definition}));
  assert.ok(MAX_ROTH_PER_USER > 0);
  assert.ok(MAX_CAMPAIGN_ROTH > MAX_ROTH_PER_USER);
});

test("campaign implementation is isolated from payments, dispatch, notifications and normal delivery requests", () => {
  const source = fs.readFileSync(path.join(__dirname, "roth-grant-campaigns.js"), "utf8");
  assert.match(source, /rothGrantCampaigns/);
  assert.doesNotMatch(source, /deliveryRequests/);
  assert.doesNotMatch(source, /stripe/i);
  assert.doesNotMatch(source, /sendNotification|notifyCustomer|dispatch/i);
  assert.match(source, /roth_campaign:\$\{campaignId\}:\$\{recipient\.id\}/);
  assert.match(source, /runTransaction/);
  assert.match(source, /offset \+= 400/);
  assert.match(source, /retryFailed === true/);
});

test("individual grant authority is isolated, capped and idempotent by grant identity", () => {
  const source = fs.readFileSync(path.join(__dirname, "roth-grant-campaigns.js"), "utf8");
  assert.equal(MAX_INDIVIDUAL_ROTH, MAX_ROTH_PER_USER);
  assert.match(source, /exports\.adminGrantRothToUser/);
  assert.match(source, /requireTrustedRothAdmin/);
  assert.match(source, /rothAdminGrants/);
  assert.match(source, /admin_roth_grant:\$\{grantId\}:\$\{uid\}/);
  assert.match(source, /sourceType: "admin_roth_grant"/);
  assert.match(source, /recordRothMovement/);
  assert.doesNotMatch(source, /deliveryRequests/);
  assert.doesNotMatch(source, /stripe/i);
  assert.doesNotMatch(source, /sendNotification|notifyCustomer|dispatch/i);
});

test("legacy issuance exports cannot bypass the canonical grant and campaign authorities", () => {
  const indexSource = fs.readFileSync(path.join(__dirname, "index.js"), "utf8");
  assert.match(indexSource, /exports\.adminGrantRothToUser/);
  assert.doesNotMatch(indexSource, /exports\.issueRothCredit\s*=/);
  assert.doesNotMatch(indexSource, /exports\.issueRothToWallets\s*=/);
});

test("campaign reconciliation rejects corrupted recipient identity, amount or ledger linkage", () => {
  const recipients = [
    {id: "user-1", data: () => ({uid: "user-1", amountRoth: 5, ledgerEntryId: "tx-1"})},
    {id: "user-2", data: () => ({uid: "user-2", amountRoth: 5, ledgerEntryId: "tx-2"})},
  ];
  const ledger = [
    {id: "tx-1", data: () => ({uid: "user-1", amount: 5, metadata: {sourceType: "roth_grant_campaign"}})},
    {id: "tx-2", data: () => ({uid: "user-2", amount: 5, metadata: {sourceType: "roth_grant_campaign"}})},
  ];
  assert.equal(reconcileGrantRecords(recipients, ledger), true);
  assert.equal(reconcileGrantRecords(recipients, ledger.map((entry, index) => index === 1 ? {...entry, data: () => ({uid: "user-1", amount: 5, metadata: {sourceType: "roth_grant_campaign"}})} : entry)), false);
  assert.equal(reconcileGrantRecords(recipients, ledger.map((entry, index) => index === 1 ? {...entry, data: () => ({uid: "user-2", amount: 4, metadata: {sourceType: "roth_grant_campaign"}})} : entry)), false);
  assert.equal(reconcileGrantRecords(recipients, ledger.map((entry, index) => index === 1 ? {...entry, data: () => ({uid: "user-2", amount: 5, metadata: {sourceType: "other"}})} : entry)), false);
});
