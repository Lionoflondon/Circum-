"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const healthEvidence = require("./health-plus-evidence");

function bucket(metadata) {
  return {file: () => ({exists: async () => [true], getMetadata: async () => [metadata]})};
}

test("Health+ evidence verifies canonical immutable Storage identity", async () => {
  const reference = await healthEvidence._private.verifyHealthEvidence({
    bucket: bucket({contentType: "image/jpeg", size: "2048", generation: "42", md5Hash: "checksum", timeCreated: "2030-01-01T00:00:00Z", metadata: {pickupId: "health-1", evidenceType: "custody", uploadedBy: "rider-1"}}),
    pickupId: "health-1", evidenceType: "custody", storagePath: "health_delivery_evidence/health-1/custody/photo.jpg", riderId: "rider-1",
  });
  assert.equal(reference.generation, "42");
  assert.equal(reference.checksum, "checksum");
  assert.equal(reference.immutable, true);
  assert.equal(reference.context.pickupId, "health-1");
});

test("Health+ evidence rejects cross-pickup and forged uploader metadata", async () => {
  const common = {pickupId: "health-1", evidenceType: "custody", storagePath: "health_delivery_evidence/health-1/custody/photo.jpg", riderId: "rider-1"};
  await assert.rejects(() => healthEvidence._private.verifyHealthEvidence({...common, bucket: bucket({contentType: "image/jpeg", size: "10", generation: "1", metadata: {pickupId: "health-2", evidenceType: "custody", uploadedBy: "rider-1"}})}));
  await assert.rejects(() => healthEvidence._private.verifyHealthEvidence({...common, bucket: bucket({contentType: "image/jpeg", size: "10", generation: "1", metadata: {pickupId: "health-1", evidenceType: "custody", uploadedBy: "rider-2"}})}));
});

test("Health+ evidence callable is App Check protected and timeline correlated", () => {
  const source = require("node:fs").readFileSync("health-plus-evidence.js", "utf8");
  assert.match(source, /runWith\(\{enforceAppCheck: true\}\)/);
  assert.match(source, /healthPlusCustodyArchive/);
  assert.match(source, /appendOperationalEvent/);
  assert.doesNotMatch(source, /downloadURL|signedUrl/);
});
