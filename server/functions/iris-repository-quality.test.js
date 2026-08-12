const test = require("node:test");
const assert = require("node:assert/strict");
const {classifyIris, verifiedCanonicalWeight} = require("./iris-core");

const promoted = (extra = {}) => ({
  id: "catalogue-item",
  canonicalName: "Example laptop",
  category: "Electronics",
  status: "active",
  repositoryReviewStatus: "promoted",
  ...extra,
});

test("generic promoted weights cannot become canonical weight authority", () => {
  const result = classifyIris({
    description: "Example laptop",
    declaredWeightText: "2 kg",
    canonicalKnowledge: [promoted({knownWeight: 900})],
  });
  assert.notEqual(result.recommendation.estimatedWeightKg, 900);
  assert.equal(result.internal.canonicalWeightEvidence, null);
});

test("manufacturer packaged weight requires exact model and evidence reference", () => {
  assert.equal(verifiedCanonicalWeight(promoted({
    knownWeight: 2.4,
    weightBasis: "manufacturer_packaged",
    weightEvidenceStatus: "verified",
  })), null);
  assert.deepEqual(verifiedCanonicalWeight(promoted({
    packagedWeightKg: 2.4,
    weightBasis: "manufacturer_packaged",
    weightEvidenceStatus: "verified",
    modelIdentifier: "MODEL-123",
    weightSourceReference: "manufacturer-spec-2026-08",
  })), {
    weightKg: 2.4,
    basis: "manufacturer_packaged",
    modelIdentifier: "MODEL-123",
    sourceReference: "manufacturer-spec-2026-08",
  });
});

test("verified scale weight requires an immutable verification identity", () => {
  assert.equal(verifiedCanonicalWeight(promoted({
    knownWeightKg: 7.25,
    weightBasis: "verified_scale",
    weightEvidenceStatus: "verified",
  })), null);
  assert.deepEqual(verifiedCanonicalWeight(promoted({
    knownWeightKg: 7.25,
    weightBasis: "verified_scale",
    weightEvidenceStatus: "verified",
    weightVerificationId: "weigh_event_delivery_123",
  })), {
    weightKg: 7.25,
    basis: "verified_scale",
    verificationId: "weigh_event_delivery_123",
  });
});

test("unreasonable and unverified weights fail closed", () => {
  assert.equal(verifiedCanonicalWeight(promoted({
    knownWeight: 1001,
    weightBasis: "verified_scale",
    weightEvidenceStatus: "verified",
    weightVerificationId: "bad",
  })), null);
  assert.equal(verifiedCanonicalWeight(promoted({
    knownWeight: 3,
    weightBasis: "verified_scale",
    weightEvidenceStatus: "pending",
    weightVerificationId: "pending",
  })), null);
});
