"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const core = require("./delivery-evidence-core");

test("canonical photo path is stable", () => {
  assert.equal(core.photoStoragePath("delivery-1", "photo-1"), "deliveries/delivery-1/evidence/photos/photo-1.jpg");
});

test("photo metadata must match the canonical immutable path", () => {
  assert.equal(core.validatePhotoInput({
    deliveryId: "delivery-1", photoId: "photo-1",
    storagePath: "deliveries/delivery-1/evidence/photos/photo-1.jpg",
    mimeType: "image/jpeg", fileSize: 1200,
  }).valid, true);
  assert.equal(core.validatePhotoInput({
    deliveryId: "delivery-1", photoId: "photo-1",
    storagePath: "delivery_weight_evidence/delivery-1/pickup/photo.jpg",
    mimeType: "image/jpeg", fileSize: 1200,
  }).valid, false);
});

test("completion is blocked until a verified photo exists", () => {
  assert.equal(core.completionEvidenceDecision({}).allowed, false);
  assert.equal(core.completionEvidenceDecision({photoCount: 1}).allowed, true);
});
