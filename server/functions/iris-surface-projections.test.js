"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {classifyIris} = require("./iris-core");
const {projectIrisForSurface} = require("./iris-surface-projections");

test("surface projections share one IRIS result without leaking private fields", () => {
  const iris = classifyIris({description: "fragile laptop with battery", declaredWeightText: "3 kg"});
  const sender = projectIrisForSurface(iris, "sender");
  const rider = projectIrisForSurface(iris, "rider", {paidWeightBand: "0–5 kg", discrepancyAllowed: true});
  const business = projectIrisForSurface(iris, "business", {slaRelevant: true});
  const admin = projectIrisForSurface(iris, "admin");
  assert.equal(sender.engineVersion, iris.engineVersion);
  assert.equal(rider.paidWeightBand, "0–5 kg");
  assert.equal(rider.discrepancyAllowed, true);
  assert.equal(business.slaRelevant, true);
  assert.equal("confidence" in business, false);
  assert.equal("riskScore" in sender, false);
  assert.ok(admin.confidence);
});

test("Health projection hides medical description and Gifts omit private story data", () => {
  const healthIris = classifyIris({description: "named patient insulin prescription", workflow: "Health+"});
  const health = projectIrisForSurface(healthIris, "health+", {coldChainRequired: true, recipientVerificationRequired: true});
  assert.equal(health.itemLabel, "Medical parcel");
  assert.equal(JSON.stringify(health).includes("patient"), false);
  assert.equal(JSON.stringify(health).includes("insulin"), false);

  const giftIris = classifyIris({description: "fragile flowers", workflow: "Gift"});
  const gift = projectIrisForSurface(giftIris, "gifts", {substitutionConstraints: ["same_category"]});
  assert.deepEqual(gift.substitutionConstraints, ["same_category"]);
  assert.equal("recipient" in gift, false);
  assert.equal("story" in gift, false);
});

test("Scheduled, Vanguard and Heavy Duty are projections, not classifiers", () => {
  const iris = classifyIris({description: "60 kg cabinet"});
  assert.equal(projectIrisForSurface(iris, "scheduled", {scheduledJourneyAt: "2026-08-12T08:00:00Z"}).timingSensitive, true);
  assert.equal(projectIrisForSurface(iris, "vanguard").enhancedVerification, true);
  assert.equal(projectIrisForSurface(iris, "heavy_duty").collectionHoldIfUnsuitable, true);
});
