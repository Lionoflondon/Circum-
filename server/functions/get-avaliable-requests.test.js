/* eslint-disable max-len */
"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");

test("Rider nearby request lookup is bounded and locality-first", () => {
  const source = fs.readFileSync("get-avaliable-requests.js", "utf8");
  assert.match(source, /const REQUEST_SCAN_LIMIT = 100;/);
  assert.match(source, /async function candidateRequestDocs\(db, riderData = \{\}\)/);
  assert.match(source, /where\("pickupLocality", "==", locality\)[\s\S]*?limit\(REQUEST_SCAN_LIMIT\)/);
  assert.match(source, /where\("matchingStatus", "in", \["available", "broadcasted"\]\)[\s\S]*?limit\(REQUEST_SCAN_LIMIT\)/);
  assert.match(source, /where\("dispatchStatus", "in", \["requested", "broadcasted"\]\)[\s\S]*?limit\(REQUEST_SCAN_LIMIT\)/);
  assert.match(source, /where\("dispatchStatus", "in", \["requested", "broadcasted"\]\)[\s\S]*?limit\(REQUEST_SCAN_LIMIT\)/);
  assert.match(source, /where\("status", "==", "requested"\)[\s\S]*?limit\(REQUEST_SCAN_LIMIT\)/);
  assert.match(source, /const requestDocs = await candidateRequestDocs\(db, riderData\);/);
  assert.match(source, /functions\.runWith\(\{enforceAppCheck: true\}\)/);
  assert.match(source, /dispatchEligibilityDecision\(\{/);
  assert.match(source, /riderOfferProjection/);
  assert.match(source, /function offerExclusionReason\(delivery = \{\}, now = Date\.now\(\)\)/);
  assert.match(source, /terminalStatuses/);
  assert.match(source, /already_assigned/);
  assert.match(source, /expired_offer/);
  assert.match(source, /payment_not_confirmed/);
  assert.match(source, /rider_offer_scan/);
  assert.match(source, /rider_offer_returned/);
  assert.doesNotMatch(source, /where\("status", "==", "requested"\)[\s\S]{0,120}\.get\(\);[\s\S]{0,120}requestsSnapshot\.docs/);
});
