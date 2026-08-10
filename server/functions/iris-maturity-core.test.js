"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {
  RISK_RESOLUTIONS,
  confidenceProfile,
  healthProjection,
  knowledgeQualityCandidates,
  latencyBucketKey,
  percentileFromBuckets,
  riskResolution,
  requestFingerprint,
} = require("./iris-maturity-core");

test("confidence is derived from evidence and bounded into stable bands", () => {
  const canonical = confidenceProfile({description: "calibrated medical parcel", canonicalMatch: {canonicalId: "known"}, declaredWeightText: "2 kg", complianceStatus: "allowed"});
  const sparse = confidenceProfile({description: "box", complianceStatus: "allowed"});
  const conflicting = confidenceProfile({description: "boxed television", shipmentItems: [{id: "tv"}], complianceStatus: "allowed", weightAuthority: {candidates: [{value: 5}, {value: 40}]}});
  assert.equal(canonical.band, "HIGH");
  assert.equal(sparse.band, "LOW");
  assert.ok(conflicting.score < confidenceProfile({description: "boxed television", shipmentItems: [{id: "tv"}], complianceStatus: "allowed"}).score);
  for (const profile of [canonical, sparse, conflicting]) assert.ok(profile.score >= 20 && profile.score <= 97);
});

test("request reuse fingerprint is deterministic and version-scoped", () => {
  const input = {description: "Laptop", weight: "2 kg"};
  const first = requestFingerprint({uid: "sender-1", input, engineVersion: "e1", knowledgeVersion: "k1"});
  assert.equal(first, requestFingerprint({uid: "sender-1", input, engineVersion: "e1", knowledgeVersion: "k1"}));
  assert.notEqual(first, requestFingerprint({uid: "sender-1", input, engineVersion: "e1", knowledgeVersion: "k2"}));
});

test("data quality audit creates bounded governed review candidates", () => {
  const candidates = knowledgeQualityCandidates([
    {id: "a", canonicalName: "Laptop", category: "Electronics", knownWeight: 2},
    {id: "b", canonicalName: "Laptop", category: "Computers", knownWeight: 3},
    {id: "c", canonicalName: "", category: null, knownWeight: null},
  ]);
  assert.ok(candidates.some((item) => item.type === "conflicting_label"));
  assert.ok(candidates.some((item) => item.type === "missing_identity"));
  assert.ok(candidates.some((item) => item.type === "missing_coverage"));
});

test("risk resolution uses the complete bounded operational taxonomy", () => {
  const results = [
    riskResolution({compliance: {status: "allowed"}}),
    riskResolution({compliance: {status: "unsupported", reasonCodes: ["insufficient_item_description"]}}),
    riskResolution({compliance: {status: "allowed"}, handlingFlags: ["Battery"]}),
    riskResolution({compliance: {status: "unsupported", reasonCodes: ["specialist_service_required"]}}),
    riskResolution({compliance: {status: "prohibited", reasonCodes: ["prohibited_item"]}}),
  ];
  assert.deepEqual(results.map((result) => result.resolution), RISK_RESOLUTIONS);
  assert.ok(results[1].targetedQuestions.length > 0);
});

test("latency buckets provide deterministic bounded percentiles", () => {
  assert.equal(latencyBucketKey(249), "lte_250");
  assert.equal(latencyBucketKey(4590), "lte_5000");
  assert.equal(latencyBucketKey(11000), "gt_10000");
  const buckets = {lte_250: 50, lte_1000: 40, lte_5000: 9, gt_10000: 1};
  assert.equal(percentileFromBuckets(buckets, 0.5), 250);
  assert.equal(percentileFromBuckets(buckets, 0.95), 5000);
  assert.equal(percentileFromBuckets(buckets, 0.99), 5000);
});

test("health projection reports only count-backed quality and performance metrics", () => {
  const result = healthProjection({requestCount: 100, latencyBuckets: {lte_250: 50, lte_1000: 45, lte_5000: 5}, failureCount: 2, timeoutCount: 1, lowConfidenceCount: 10, fastPathCount: 40, riderDisagreementCount: 4, adminOverrideCount: 3, adjudicatedTruthCount: 8, classificationAdjudicatedCount: 8, classificationCorrectCount: 6, weightBandAdjudicatedCount: 8, weightBandCorrectCount: 7});
  assert.equal(result.failureRatePercent, 2);
  assert.equal(result.lowConfidenceRatePercent, 10);
  assert.equal(result.fastPathRatePercent, 40);
  assert.equal(result.adjudicatedTruthCount, 8);
  assert.equal(result.classificationCorrectCount, 6);
  assert.equal(result.weightBandCorrectCount, 7);
  assert.equal(result.classificationAccuracyPercent, 75);
  assert.equal(result.weightBandAccuracyPercent, 87.5);
});
