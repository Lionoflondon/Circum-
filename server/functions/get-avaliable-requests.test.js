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
  assert.match(source, /const requestDocs = await candidateRequestDocs\(getFirestore\(\), riderData\);/);
  assert.match(source, /function offerExclusionReason\(delivery = \{\}, now = Date\.now\(\)\)/);
  assert.match(source, /terminalStatuses/);
  assert.match(source, /already_assigned/);
  assert.match(source, /expired_offer/);
  assert.match(source, /payment_not_confirmed/);
  assert.match(source, /rider_offer_scan/);
  assert.match(source, /rider_offer_returned/);
  assert.doesNotMatch(source, /where\("status", "==", "requested"\)[\s\S]{0,120}\.get\(\);[\s\S]{0,120}requestsSnapshot\.docs/);
});

test("dispatch broadcast validates geos without rejecting explicit zero coordinates", () => {
  const sendPackage = require("./send-package");
  const {canonicalGeoPoint} = sendPackage._private;
  assert.deepEqual(canonicalGeoPoint({geopoint: {latitude: 0, longitude: 0}}), {
    latitude: 0,
    longitude: 0,
  });
  assert.equal(canonicalGeoPoint(null), null);
  assert.equal(canonicalGeoPoint({}), null);
  assert.equal(canonicalGeoPoint({geopoint: {latitude: 51.5}}), null);
  assert.equal(canonicalGeoPoint({geopoint: {latitude: "north", longitude: 0}}), null);

  const source = fs.readFileSync("send-package.js", "utf8");
  assert.match(source, /reason: "missing_pickup_geo"/);
  assert.doesNotMatch(source, /riderData\.position\.geopoint\.latitude\s*&&/);
  assert.doesNotMatch(source, /riderLocation\.latitude\s*\|\|/);
});
