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
  assert.equal(core.validatePhotoInput({
    deliveryId: "delivery-1", photoId: "photo-1",
    storagePath: "deliveries/delivery-1/evidence/photos/photo-1.jpg",
    mimeType: "image/png", fileSize: 1200,
  }).valid, false);
  assert.equal(core.validatePhotoInput({
    deliveryId: "delivery-1", photoId: "photo-1",
    storagePath: "deliveries/delivery-1/evidence/photos/photo-1.jpg",
    mimeType: "image/jpeg", fileSize: 0,
  }).valid, false);
  assert.equal(core.validatePhotoInput({
    deliveryId: "delivery-1", photoId: "photo-1",
    storagePath: "deliveries/delivery-1/evidence/photos/photo-1.jpg",
    mimeType: "image/jpeg", fileSize: 16 * 1024 * 1024,
  }).valid, false);
});

test("completion is blocked until a verified photo exists", () => {
  assert.equal(core.completionEvidenceDecision({}).allowed, false);
  assert.equal(core.completionEvidenceDecision({photoCount: 1}).allowed, true);
});

test("thumbnail-only photo records are not treated as verified evidence", () => {
  assert.equal(core.isVerifiedPhotoRecord({
    thumbnailPath: "deliveries/d-1/evidence/thumbnails/p-1.jpg",
    thumbnailGeneratedAt: "server-timestamp",
  }), false);
  assert.equal(core.isVerifiedPhotoRecord({immutable: true, verified: false}), false);
  assert.equal(core.isVerifiedPhotoRecord({immutable: true, verified: true}), true);
});

function pickupPhoto(overrides = {}) {
  return {
    id: "photo-1", deliveryId: "delivery-1", uploadedBy: "rider-1",
    storagePath: "deliveries/delivery-1/evidence/photos/photo-1.jpg",
    generation: "42", checksum: "checksum", mimeType: "image/jpeg", fileSize: 1200,
    purpose: "PICKUP", immutable: true, verified: true, ...overrides,
  };
}

test("Vanguard pickup accepts only immutable evidence for this delivery, rider and phase", () => {
  const expected = {deliveryId: "delivery-1", riderId: "rider-1", photoId: "photo-1", purpose: "PICKUP"};
  assert.equal(core.transitionEvidenceDecision(pickupPhoto(), expected).allowed, true);
  assert.equal(core.transitionEvidenceDecision(pickupPhoto({deliveryId: "delivery-2"}), expected).allowed, false);
  assert.equal(core.transitionEvidenceDecision(pickupPhoto({uploadedBy: "rider-2"}), expected).allowed, false);
  assert.equal(core.transitionEvidenceDecision(pickupPhoto({purpose: "HANDOVER"}), expected).allowed, false);
  assert.equal(core.transitionEvidenceDecision(pickupPhoto({purpose: "DISCREPANCY"}), expected).allowed, false);
  assert.equal(core.transitionEvidenceDecision(pickupPhoto({generation: null}), expected).allowed, false);
  assert.equal(core.transitionEvidenceDecision(pickupPhoto({storagePath: "https://example.invalid/photo.jpg"}), expected).allowed, false);
  assert.equal(core.transitionEvidenceDecision({id: "photo-1"}, expected).allowed, false);
});
