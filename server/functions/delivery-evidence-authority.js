/* eslint-disable max-len, require-jsdoc */
const functions = require("firebase-functions/v1");
const {getStorage} = require("firebase-admin/storage");

function evidencePath(photoUrl, bucketName, deliveryId, stage) {
  let url;
  try {
    url = new URL(photoUrl);
  } catch (_) {
    return null;
  }
  if (
    url.protocol !== "https:" ||
    url.hostname !== "firebasestorage.googleapis.com"
  ) {
    return null;
  }
  const prefix = `/v0/b/${bucketName}/o/`;
  if (!url.pathname.startsWith(prefix)) return null;
  let path;
  try {
    path = decodeURIComponent(url.pathname.slice(prefix.length));
  } catch (_) {
    return null;
  }
  const expected = `delivery_weight_evidence/${deliveryId}/${stage}/`;
  return path.startsWith(expected) &&
    /^[0-9]+\.jpg$/.test(path.slice(expected.length)) ?
    path :
    null;
}

async function verifyDeliveryEvidence({
  photoUrl,
  deliveryId,
  riderId,
  stage,
  bucket = getStorage().bucket(),
}) {
  const path = evidencePath(photoUrl, bucket.name, deliveryId, stage);
  if (!path) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Upload a photo for this delivery and evidence stage.",
    );
  }
  let metadata;
  try {
    [metadata] = await bucket.file(path).getMetadata();
  } catch (_) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Delivery evidence upload was not found.",
    );
  }
  const custom = metadata.metadata || {};
  if (
    custom.deliveryId !== deliveryId ||
    custom.uploadedBy !== riderId ||
    custom.evidenceType !== "weight_discrepancy" ||
    metadata.contentType !== "image/jpeg" ||
    !(Number(metadata.size) > 0 && Number(metadata.size) <= 15 * 1024 * 1024)
  ) {
    throw new functions.https.HttpsError(
      "permission-denied",
      "Delivery evidence does not belong to this rider and delivery.",
    );
  }
  return path;
}
module.exports = {evidencePath, verifyDeliveryEvidence};
