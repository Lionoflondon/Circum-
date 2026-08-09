/* eslint-disable max-len, require-jsdoc */
"use strict";

const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {getStorage} = require("firebase-admin/storage");
const sharp = require("sharp");

const PHOTO_PATH = /^deliveries\/([^/]+)\/evidence\/photos\/([A-Za-z0-9_-]+)\.jpg$/;

exports.onDeliveryEvidencePhotoFinalized = functions.storage.object().onFinalize(async (object) => {
  const name = `${object.name || ""}`;
  const match = name.match(PHOTO_PATH);
  if (!match || `${object.contentType || ""}`.toLowerCase() !== "image/jpeg") return null;
  const [, deliveryId, photoId] = match;
  const bucket = getStorage().bucket(object.bucket);
  const source = bucket.file(name);
  const [buffer] = await source.download();
  const thumbnail = await sharp(buffer)
      .resize(640, 640, {fit: "inside", withoutEnlargement: true})
      .jpeg({quality: 78})
      .toBuffer();
  const thumbnailPath = `deliveries/${deliveryId}/evidence/thumbnails/${photoId}.jpg`;
  await bucket.file(thumbnailPath).save(thumbnail, {
    resumable: false,
    metadata: {contentType: "image/jpeg", metadata: {sourcePath: name}},
  });
  await getFirestore().collection("deliveryEvidence").doc(deliveryId)
      .collection("photos").doc(photoId).set({
        thumbnailPath,
        thumbnailGeneratedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
  return {deliveryId, photoId, thumbnailPath};
});
