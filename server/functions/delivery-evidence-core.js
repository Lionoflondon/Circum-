"use strict";

const crypto = require("crypto");

const PHOTO = "PHOTO";
const PHOTO_PATH = /^deliveries\/([^/]+)\/evidence\/photos\/([^/]+)\.jpg$/;

function text(value) {
  return `${value || ""}`.trim();
}

function positiveNumber(value) {
  const number = Number(value);
  return Number.isFinite(number) && number >= 0 ? number : null;
}

function photoStoragePath(deliveryId, photoId) {
  return `deliveries/${text(deliveryId)}/evidence/photos/${text(photoId)}.jpg`;
}

function validatePhotoInput(input = {}) {
  const deliveryId = text(input.deliveryId);
  const photoId = text(input.photoId);
  const storagePath = text(input.storagePath);
  if (!deliveryId || !photoId || !storagePath) {
    return {valid: false, reason: "deliveryId, photoId and storagePath are required."};
  }
  const match = storagePath.match(PHOTO_PATH);
  if (!match || match[1] !== deliveryId || match[2] !== photoId) {
    return {valid: false, reason: "Evidence storage path is not canonical."};
  }
  if (text(input.type || PHOTO) !== PHOTO) {
    return {valid: false, reason: "Only PHOTO evidence is currently supported."};
  }
  const mimeType = text(input.mimeType || "image/jpeg").toLowerCase();
  if (mimeType !== "image/jpeg") {
    return {valid: false, reason: "Delivery evidence must be a JPEG photo."};
  }
  const fileSize = positiveNumber(input.fileSize);
  if (fileSize === null || fileSize <= 0 || fileSize > 15 * 1024 * 1024) {
    return {valid: false, reason: "Evidence photo file size is invalid."};
  }
  return {valid: true, deliveryId, photoId, storagePath, mimeType, fileSize};
}

function completionEvidenceDecision(evidence = {}) {
  const count = Number(evidence.verifiedPhotoCount || evidence.photoCount || 0);
  if (!Number.isInteger(count) || count < 1) {
    return {allowed: false, reason: "A verified delivery evidence photo is required before completion."};
  }
  return {allowed: true, reason: "Verified delivery evidence is present."};
}

function isVerifiedPhotoRecord(photo = {}) {
  return photo.immutable === true && photo.verified === true;
}

function evidencePurpose(value) {
  const purpose = text(value).toUpperCase();
  return ["PICKUP", "HANDOVER", "DISCREPANCY"].includes(purpose) ? purpose : null;
}

function transitionEvidenceDecision(photo = {}, expected = {}) {
  const purpose = evidencePurpose(expected.purpose);
  if (!isVerifiedPhotoRecord(photo)) return {allowed: false, reason: "Verified delivery evidence was not found."};
  if (!purpose || evidencePurpose(photo.purpose || photo.context?.purpose) !== purpose) {
    return {allowed: false, reason: "Delivery evidence does not match this lifecycle phase."};
  }
  if (text(photo.deliveryId) !== text(expected.deliveryId) || text(photo.uploadedBy) !== text(expected.riderId)) {
    return {allowed: false, reason: "Delivery evidence ownership does not match this delivery."};
  }
  const expectedPath = photoStoragePath(expected.deliveryId, expected.photoId);
  if (text(photo.id) !== text(expected.photoId) || text(photo.storagePath) !== expectedPath) {
    return {allowed: false, reason: "Delivery evidence storage identity is invalid."};
  }
  if (!text(photo.generation) || !text(photo.checksum) || !text(photo.mimeType) ||
      !(positiveNumber(photo.fileSize) > 0)) {
    return {allowed: false, reason: "Delivery evidence immutable metadata is incomplete."};
  }
  return {allowed: true, evidence: {
    photoId: text(photo.id), storagePath: text(photo.storagePath), generation: text(photo.generation),
    checksum: text(photo.checksum), mimeType: text(photo.mimeType), fileSize: positiveNumber(photo.fileSize), purpose,
  }};
}

function evidenceSummary(photo, uploaderId) {
  return {
    type: PHOTO,
    storagePath: photo.storagePath,
    thumbnailPath: photo.thumbnailPath || null,
    uploadedBy: uploaderId,
    capturedAt: photo.capturedAt || null,
    checksum: photo.checksum || null,
    generation: text(photo.generation) || null,
    purpose: evidencePurpose(photo.purpose || photo.context?.purpose),
    context: photo.context || null,
    mimeType: photo.mimeType,
    width: positiveNumber(photo.width),
    height: positiveNumber(photo.height),
    fileSize: photo.fileSize,
    gps: photo.gps || null,
    accuracy: positiveNumber(photo.accuracy),
    orientation: text(photo.orientation) || null,
    device: text(photo.device) || null,
  };
}

function immutableStorageReference({storagePath, metadata = {}, uploadedBy, deliveryId, context = {}, maxBytes = 15 * 1024 * 1024}) {
  const contentType = text(metadata.contentType).toLowerCase();
  const size = Number(metadata.size);
  const generation = text(metadata.generation);
  if (!storagePath || !generation || !contentType.match(/^image\/(jpeg|png|webp)$/) || !Number.isFinite(size) || size <= 0 || size > maxBytes) {
    throw new Error("Evidence upload metadata is invalid.");
  }
  return Object.freeze({
    evidenceId: crypto.createHash("sha256").update(`${storagePath}|${generation}`).digest("hex").slice(0, 40),
    storagePath,
    generation,
    checksum: text(metadata.md5Hash) || null,
    mimeType: contentType,
    size,
    uploadedAt: metadata.timeCreated || null,
    uploadedBy: text(uploadedBy),
    deliveryId: text(deliveryId) || null,
    context,
    immutable: true,
    verified: true,
  });
}

module.exports = {
  PHOTO,
  photoStoragePath,
  validatePhotoInput,
  completionEvidenceDecision,
  isVerifiedPhotoRecord,
  evidencePurpose,
  transitionEvidenceDecision,
  evidenceSummary,
  immutableStorageReference,
};
