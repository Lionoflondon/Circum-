/* eslint-disable require-jsdoc */
"use strict";

const crypto = require("crypto");

const MAX_BYTES = 15 * 1024 * 1024;
const PATHS = [
  /^delivery-discrepancies\/([^/]+)\/([^/]+)\/([^/]+\.(?:jpg|jpeg|png|webp|pdf))$/i,
  /^delivery_weight_evidence\/([^/]+)\/([^/]+)\/([^/]+\.(?:jpg|jpeg|png|webp|pdf))$/i,
];
const MIME_TYPES = new Set(["image/jpeg", "image/png", "image/webp", "application/pdf"]);

function text(value) {
  return `${value || ""}`.trim();
}

function storagePathFrom(value) {
  if (value && typeof value === "object") return text(value.storagePath || value.fullPath);
  const raw = text(value);
  if (!raw.includes("://")) return raw;
  const match = raw.match(/\/o\/([^?]+)/);
  return match ? decodeURIComponent(match[1]) : "";
}

function validateReference(value, deliveryId, riderId) {
  const storagePath = storagePathFrom(value);
  const matched = PATHS.map((pattern, index) => ({index, match: storagePath.match(pattern)})).find((item) => item.match);
  const match = matched && matched.match;
  if (!match || match[1] !== deliveryId || (matched.index === 0 && match[2] !== riderId)) {
    throw new Error("Evidence storage path is not canonical for this delivery and rider.");
  }
  return storagePath;
}

function immutableReference({storagePath, metadata, deliveryId, discrepancyId, riderId}) {
  const contentType = text(metadata.contentType).toLowerCase();
  const size = Number(metadata.size);
  const generation = text(metadata.generation);
  if (!MIME_TYPES.has(contentType) || !Number.isFinite(size) || size <= 0 || size > MAX_BYTES || !generation) {
    throw new Error("Evidence upload metadata is invalid.");
  }
  const custom = metadata.metadata || {};
  if ((custom.deliveryId && custom.deliveryId !== deliveryId) ||
      (custom.uploadedBy && custom.uploadedBy !== riderId)) {
    throw new Error("Evidence upload ownership metadata does not match.");
  }
  return Object.freeze({
    evidenceId: crypto.createHash("sha256").update(`${storagePath}|${generation}`).digest("hex").slice(0, 40),
    storagePath,
    generation,
    checksum: text(metadata.md5Hash) || null,
    contentType,
    size,
    uploadedAt: metadata.timeCreated || null,
    uploadedBy: riderId,
    deliveryId,
    discrepancyId,
    immutable: true,
    verified: true,
  });
}

async function verifyReferences({bucket, references, deliveryId, discrepancyId, riderId}) {
  const unique = [...new Set(references.map((value) => validateReference(value, deliveryId, riderId)))];
  const verified = [];
  for (const storagePath of unique) {
    const [exists] = await bucket.file(storagePath).exists();
    if (!exists) throw new Error("Evidence upload was not found.");
    const [metadata] = await bucket.file(storagePath).getMetadata();
    verified.push(immutableReference({storagePath, metadata, deliveryId, discrepancyId, riderId}));
  }
  return verified;
}

module.exports = {MAX_BYTES, immutableReference, storagePathFrom, validateReference, verifyReferences};
