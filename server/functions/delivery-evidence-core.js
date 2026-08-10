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

function evidenceSummary(photo, uploaderId) {
  return {
    type: PHOTO,
    storagePath: photo.storagePath,
    thumbnailPath: photo.thumbnailPath || null,
    uploadedBy: uploaderId,
    capturedAt: photo.capturedAt || null,
    checksum: photo.checksum || null,
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
  evidenceSummary,
  immutableStorageReference,
};
