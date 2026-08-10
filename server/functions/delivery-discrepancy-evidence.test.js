"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const evidence = require("./delivery-discrepancy-evidence");

test("canonical discrepancy evidence preserves immutable Storage identity", () => {
  const storagePath = "delivery-discrepancies/delivery-1/rider-1/photo.jpg";
  const result = evidence.immutableReference({
    storagePath,
    deliveryId: "delivery-1",
    discrepancyId: "case-1",
    riderId: "rider-1",
    metadata: {
      contentType: "image/jpeg",
      size: "1024",
      generation: "7",
      md5Hash: "checksum",
      timeCreated: "2026-08-10T10:00:00.000Z",
      metadata: {deliveryId: "delivery-1", uploadedBy: "rider-1"},
    },
  });
  assert.equal(result.storagePath, storagePath);
  assert.equal(result.generation, "7");
  assert.equal(result.checksum, "checksum");
  assert.equal(result.uploadedBy, "rider-1");
  assert.equal(result.verified, true);
  assert.equal(Object.isFrozen(result), true);
});

test("evidence path cannot cross delivery or rider authority", () => {
  assert.throws(() => evidence.validateReference(
      "delivery-discrepancies/delivery-2/rider-1/photo.jpg", "delivery-1", "rider-1",
  ));
  assert.throws(() => evidence.validateReference(
      "delivery-discrepancies/delivery-1/rider-2/photo.jpg", "delivery-1", "rider-1",
  ));
  assert.throws(() => evidence.validateReference("https://example.test/photo.jpg", "delivery-1", "rider-1"));
});

test("legacy Firebase download URL is parsed but still validated canonically", () => {
  const path = "delivery-discrepancies/delivery-1/rider-1/photo.jpg";
  const url = `https://firebasestorage.googleapis.com/v0/b/bucket/o/${encodeURIComponent(path)}?alt=media`;
  assert.equal(evidence.validateReference(url, "delivery-1", "rider-1"), path);
});

test("native Rider legacy path converges into the same verified evidence authority", () => {
  const path = "delivery_weight_evidence/delivery-1/discrepancy/photo.jpg";
  assert.equal(evidence.validateReference(path, "delivery-1", "rider-1"), path);
});

test("evidence rejects unsafe metadata and mismatched ownership", () => {
  const base = {
    storagePath: "delivery-discrepancies/delivery-1/rider-1/photo.jpg",
    deliveryId: "delivery-1",
    discrepancyId: "case-1",
    riderId: "rider-1",
  };
  assert.throws(() => evidence.immutableReference({...base, metadata: {contentType: "text/html", size: 5, generation: "1"}}));
  assert.throws(() => evidence.immutableReference({...base, metadata: {contentType: "image/jpeg", size: 5, generation: "1", metadata: {uploadedBy: "rider-2"}}}));
});
