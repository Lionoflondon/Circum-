"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const source = fs.readFileSync(path.join(__dirname, "google-play-reviewer-provisioning.js"), "utf8");
const index = fs.readFileSync(path.join(__dirname, "index.js"), "utf8");

test("provisioning is founder and App Check protected", () => {
  assert.match(source, /onCall\(\{enforceAppCheck: true\}/);
  assert.match(source, /context\.auth\.uid !== FOUNDER_RIDER_UID/);
  assert.match(index, /provisionGooglePlayReviewer/);
});

test("provisioning writes only the fixed reviewer authority", () => {
  assert.match(source, /ACCOUNT_TYPE = "demo_account"/);
  assert.match(source, /PURPOSE = "google_play_review"/);
  assert.match(source, /accountType: ACCOUNT_TYPE/);
  assert.match(source, /purpose: PURPOSE/);
  assert.match(source, /reviewOnly: true/);
  assert.doesNotMatch(source, /workEntitledUk\s*:/);
  assert.doesNotMatch(source, /rightToWork\s*:/);
  assert.doesNotMatch(source, /(?:admin|finance|payout|settlement|dispatch)\w*\s*:/i);
});

test("provisioning is auditable, expiring and does not store passwords", () => {
  assert.match(source, /founderTestAccounts/);
  assert.match(source, /founderReviewAudit/);
  assert.match(source, /expiresAt/);
  assert.match(source, /passwordStored: false/);
  assert.match(source, /deleteUser/);
});
