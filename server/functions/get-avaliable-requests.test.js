/* eslint-disable max-len */
"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const {riderOfferProjection} = require("./get-avaliable-requests")._private;

test("Rider nearby request lookup is bounded and locality-first", () => {
  const source = fs.readFileSync("get-avaliable-requests.js", "utf8");
  assert.match(source, /const REQUEST_SCAN_LIMIT = 100;/);
  assert.match(source, /async function candidateRequestDocs\(db, riderData = \{\}\)/);
  assert.match(source, /where\("pickupLocality", "==", locality\)[\s\S]*?limit\(REQUEST_SCAN_LIMIT\)/);
  assert.match(source, /where\("matchingStatus", "==", "available"\)[\s\S]*?limit\(REQUEST_SCAN_LIMIT\)/);
  assert.match(source, /where\("dispatchStatus", "==", "requested"\)[\s\S]*?limit\(REQUEST_SCAN_LIMIT\)/);
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

test("Rider offer projection is decision-grade and excludes private addresses", () => {
  const projection = riderOfferProjection("delivery-1", {
    requestId: "request-1",
    pickupAddress: "1 Private Street",
    dropoffAddress: "2 Secret Road",
    pickupDetails: {moreInformation: "Floor 4"},
    pricingBreakdown: {
      weightKg: 8,
      journey: {
        pickup: {locality: "Camden", postcode: "NW1 1AA"},
        dropoff: {locality: "Hackney", postcode: "E8 1AA"},
        route: {distanceMiles: 6.4, durationMinutes: 28},
      },
    },
    parcel: {itemName: "Books", quantity: 2, weightKg: 4},
    iris: {itemName: "Books", quantity: 2, recommendation: {estimatedWeightKg: 8, vehicleType: "car"}},
    riderEarning: 9.5,
  }, 1.2);
  assert.equal(projection.pickupLocality, "Camden");
  assert.equal(projection.dropoffLocality, "Hackney");
  assert.equal(projection.item.chargeableWeightKg, 8);
  assert.equal(projection.item.weightBand, ">5-10 kg");
  assert.equal(projection.riderEarning, 9.5);
  assert.equal(JSON.stringify(projection).includes("Private Street"), false);
  assert.equal(JSON.stringify(projection).includes("Secret Road"), false);
  assert.equal(JSON.stringify(projection).includes("Floor 4"), false);
});
