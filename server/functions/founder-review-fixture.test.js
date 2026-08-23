"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const source = fs.readFileSync(path.join(__dirname, "founder-review-fixture.js"), "utf8");
const index = fs.readFileSync(path.join(__dirname, "index.js"), "utf8");

test("review fixture uses isolated namespaces and explicit Google Play purpose", () => {
  assert.match(source, /founderTestAccounts/);
  assert.match(source, /reviewDeliveryFixtures/);
  assert.match(source, /google_play_review/);
  assert.match(source, /demo_account/);
  assert.match(source, /riderCallable/);
  assert.doesNotMatch(source, /onCall\(\{enforceAppCheck: true\}/);
  assert.match(source, /FOUNDER_RIDER_UID/);
});

test("review fixture exports are registered without production delivery wiring", () => {
  assert.match(index, /createGooglePlayReviewFixture/);
  assert.match(index, /getGooglePlayReviewFixture/);
  assert.match(index, /updateGooglePlayReviewFixtureLocation/);
  assert.match(index, /revokeGooglePlayReviewAccount/);
  assert.doesNotMatch(source, /deliveryRequests/);
  assert.doesNotMatch(source, /stripe|riderEarnings|roth|settlement|dispatch|notification/i);
});

test("fixture authority is server-side and expires", () => {
  assert.match(source, /expiresAt <= now/);
  assert.match(source, /revokedAt/);
  assert.match(source, /fixture\.reviewerUid !== reviewerUid/);
  assert.match(source, /FIXTURE_TTL_MS/);
  assert.match(source, /founderReviewAudit/);
});
