"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const source = fs.readFileSync(path.join(__dirname, "founder-review-fixture.js"), "utf8");
const index = fs.readFileSync(path.join(__dirname, "index.js"), "utf8");
const {_private} = require("./founder-review-fixture");

function designationDb(value) {
  return {
    collection: () => ({
      doc: () => ({
        get: async () => ({exists: true, data: () => value}),
      }),
    }),
  };
}

function timestamp(milliseconds) {
  return {toMillis: () => milliseconds};
}

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

test("review designation and fixture lifetimes support asynchronous review", async () => {
  const now = Date.now();
  assert.equal(_private.REVIEWER_TTL_MS, 90 * 24 * 60 * 60 * 1000);
  assert.equal(_private.FIXTURE_TTL_MS, 30 * 24 * 60 * 60 * 1000);

  const designation = {
    enabled: true,
    accountType: _private.ACCOUNT_TYPE,
    purpose: _private.PURPOSE,
    revokedAt: null,
    expiresAt: timestamp(now + _private.REVIEWER_TTL_MS),
  };
  const afterThirtyMinutes = now + 31 * 60 * 1000;
  assert.equal(
    await _private.activeDesignation(designationDb(designation), "reviewer", afterThirtyMinutes),
    designation,
  );
});

test("expired and revoked reviewer designations fail closed server-side", async () => {
  const now = Date.now();
  const base = {
    enabled: true,
    accountType: _private.ACCOUNT_TYPE,
    purpose: _private.PURPOSE,
    revokedAt: null,
  };

  assert.equal(await _private.activeDesignation(designationDb({
    ...base,
    expiresAt: timestamp(now - 1),
  }), "reviewer", now), null);
  assert.equal(await _private.activeDesignation(designationDb({
    ...base,
    revokedAt: timestamp(now - 1),
    expiresAt: timestamp(now + _private.REVIEWER_TTL_MS),
  }), "reviewer", now), null);
});
