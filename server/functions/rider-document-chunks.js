/* eslint-disable max-len, require-jsdoc */
const crypto = require("node:crypto");
const functions = require("firebase-functions/v1");
const {getStorage} = require("firebase-admin/storage");
const CHUNK_BYTES = 2 * 1024 * 1024;
const MAX_BYTES = 8 * 1024 * 1024;
function invalid(message) {
 throw new functions.https.HttpsError("invalid-argument", message);
}
function descriptor(file) {
  if (!file || !["front", "back", "primary"].includes(file.side) ||
      !["application/pdf", "image/jpeg", "image/png", "image/webp"].includes(file.contentType) ||
      !Number.isInteger(file.sizeBytes) || file.sizeBytes < 1 || file.sizeBytes > MAX_BYTES ||
      !/^[a-f0-9]{64}$/.test(file.sha256 || "")) invalid("Invalid document upload manifest.");
  return {side: file.side, contentType: file.contentType, sizeBytes: file.sizeBytes, sha256: file.sha256,
    fileName: `${file.fileName || "document"}`.slice(0, 180)};
}
function descriptors(files) {
  if (!Array.isArray(files) || !files.length || files.length > 2) invalid("Choose one document or its front and back.");
  const result = files.map(descriptor).sort((a, b) => a.side.localeCompare(b.side));
  if (new Set(result.map((f) => f.side)).size !== result.length) invalid("Duplicate document side.");
  return result;
}
function fingerprint(files) {
 return crypto.createHash("sha256").update(JSON.stringify(descriptors(files))).digest("hex");
}
function object(uid, key, file, index) {
  if (!/^[A-Za-z0-9_-]{8,120}$/.test(key || "")) invalid("A valid upload request key is required.");
  return getStorage().bucket().file(`rider_document_chunks/${uid}/${key}/${file.side}_${file.sha256}_${index}`);
}
async function stage(uid, key, chunk) {
  const file = descriptor(chunk);
  const count = Math.ceil(file.sizeBytes / CHUNK_BYTES);
  if (!Number.isInteger(chunk.index) || chunk.index < 0 || chunk.index >= count ||
      typeof chunk.base64 !== "string" || chunk.base64.length > Math.ceil(CHUNK_BYTES / 3) * 4 ||
      !/^[A-Za-z0-9+/]*={0,2}$/.test(chunk.base64)) invalid("Invalid document chunk.");
  const bytes = Buffer.from(chunk.base64, "base64");
  const expected = Math.min(CHUNK_BYTES, file.sizeBytes - chunk.index * CHUNK_BYTES);
  if (bytes.length !== expected || bytes.toString("base64") !== chunk.base64) invalid("Invalid document chunk size.");
  await object(uid, key, file, chunk.index).save(bytes, {resumable: false, metadata: {contentType: "application/octet-stream", metadata: {riderId: uid, temporary: "true"}}});
  return {ok: true, chunkAccepted: true, index: chunk.index};
}
async function assemble(uid, key, files) {
  const result = [];
  for (const file of descriptors(files)) {
    const chunks = [];
    for (let i = 0; i < Math.ceil(file.sizeBytes / CHUNK_BYTES); i += 1) {
      const [bytes] = await object(uid, key, file, i).download();
      chunks.push(bytes);
    }
    const bytes = Buffer.concat(chunks);
    if (bytes.length !== file.sizeBytes || crypto.createHash("sha256").update(bytes).digest("hex") !== file.sha256) invalid("Document upload is incomplete. Please retry.");
    result.push({side: file.side, mimeType: file.contentType, fileName: file.fileName, base64: bytes.toString("base64")});
  }
  return result;
}
async function cleanup(uid, key, files) {
  for (const file of descriptors(files)) {
    for (let i = 0; i < Math.ceil(file.sizeBytes / CHUNK_BYTES); i += 1) {
      await object(uid, key, file, i).delete({ignoreNotFound: true}).catch(() => null);
    }
  }
}
module.exports = {stage, assemble, cleanup, fingerprint};
