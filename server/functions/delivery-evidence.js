/* eslint-disable max-len, require-jsdoc */
const crypto = require("crypto");
const functions = require("firebase-functions/v1");
const {riderCallable} = require("./rider-app-check");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {getStorage} = require("firebase-admin/storage");
const {verifyDeliveryEvidence} = require("./delivery-evidence-authority");
const text = (v) => `${v || ""}`.trim();
const stage = (v) =>
  ["pickup", "collection"].includes(text(v).toLowerCase()) ?
    "pickup" :
    ["dropoff", "handover", "delivery"].includes(text(v).toLowerCase()) ?
      "handover" :
      text(v).toLowerCase();
const TYPES = new Set([
  "image/jpeg",
  "image/png",
  "image/webp",
  "image/heic",
  "image/heif",
]);
const terminal = (d) =>
  [
    "completed",
    "complete",
    "delivered",
    "cancelled",
    "canceled",
    "failed",
    "no_show",
    "expired",
    "settlement_pending",
  ].includes(text(d.status || d.deliveryStatus).toLowerCase()) ||
  Boolean(d.cancellationSettlementStatus);
const owns = (d, uid) =>
  [d.riderId, d.driverId, d.assignedRiderId, d.assignedDriverId]
    .map(text)
    .includes(uid);
const error = (message) =>
  new functions.https.HttpsError("failed-precondition", message);
function decodeImage(data) {
  const contentType = text(data.contentType || data.mimeType || "image/jpeg")
    .replace("image/jpg", "image/jpeg")
    .toLowerCase();
  const encoded = text(
    data.imageBase64 || data.base64 || data.bytesBase64,
  ).replace(/^data:image\/[A-Za-z0-9.+-]+;base64,/, "");
  if (
    !TYPES.has(contentType) ||
    encoded.length > Math.ceil((8 * 1024 * 1024 * 4) / 3) + 16
  ) {
    throw error("Unsupported or oversized evidence image.");
  }
  const bytes = Buffer.from(encoded, "base64");
  if (!bytes.length || bytes.length > 8 * 1024 * 1024) {
    throw error("Evidence image is missing or too large.");
  }
  const matches =
    contentType === "image/jpeg" ?
      bytes.subarray(0, 3).equals(Buffer.from([255, 216, 255])) :
      contentType === "image/png" ?
        bytes
            .subarray(0, 8)
            .equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])) :
        contentType === "image/webp" ?
          bytes.subarray(0, 4).toString() === "RIFF" &&
            bytes.subarray(8, 12).toString() === "WEBP" :
          bytes.subarray(4, 8).toString() === "ftyp" &&
            /heic|heix|hevc|hevx|mif1|msf1/.test(
              bytes.subarray(8, 32).toString(),
            );
  if (!matches) throw error("The evidence bytes do not match the image type.");
  return {bytes, contentType};
}
function canonicalPath(path, deliveryId, riderId) {
  return (
    path.startsWith(`deliveryEvidence/${deliveryId}/${riderId}/`) ||
    path.startsWith(`delivery_evidence/${deliveryId}/${riderId}/`) ||
    path.startsWith(`deliveries/${deliveryId}/evidence/photos/`) ||
    path.startsWith(`delivery_weight_evidence/${deliveryId}/`)
  );
}
async function validateRecord(
  record,
  {deliveryId, riderId, requiredStage, bucket = getStorage().bucket()},
) {
  if (!record || text(record.deliveryId) !== deliveryId) {
    throw error("Evidence does not belong to this delivery.");
  }
  if (text(record.riderId || record.uploadedBy) !== riderId) {
    throw error("Evidence does not belong to this rider.");
  }
  if (
    requiredStage &&
    stage(record.stage || record.lifecycleStage) !== stage(requiredStage)
  ) {
    throw error("Evidence was recorded for the wrong stage.");
  }
  if (
    !(
      record.verified === true ||
      ["verified", "finalized", "accepted"].includes(record.status)
    )
  ) {
    throw error("Evidence is not verified.");
  }
  const path = text(
    record.storagePath ||
      record.storageObject ||
      record.canonicalMediaReference,
  );
  if (!canonicalPath(path, deliveryId, riderId) || path.includes("..")) {
    throw error("Evidence media path is not canonical.");
  }
  let metadata;
  try {
    [metadata] = await bucket.file(path).getMetadata();
  } catch (_) {
    throw error("Evidence upload was not found.");
  }
  const custom = metadata.metadata || {};
  if (
    custom.deliveryId !== deliveryId ||
    text(custom.riderId || custom.uploadedBy) !== riderId ||
    (custom.stage &&
      stage(custom.stage) !== stage(record.stage || record.lifecycleStage)) ||
    !TYPES.has(metadata.contentType) ||
    !(Number(metadata.size) > 0 && Number(metadata.size) <= 15 * 1024 * 1024) ||
    (record.contentType && record.contentType !== metadata.contentType) ||
    (record.generation && text(record.generation) !== text(metadata.generation))
  ) {
    throw error(
      "Evidence object ownership, type, size or generation is invalid.",
    );
  }
  return {
    ...record,
    storagePath: path,
    generation: text(metadata.generation),
    contentType: metadata.contentType,
    size: Number(metadata.size),
  };
}
async function resolve({
  db,
  transaction,
  deliveryId,
  riderId,
  requiredStage,
  evidence = {},
}) {
  if (evidence.evidenceId) {
    const id = text(evidence.evidenceId);
    if (!/^[A-Za-z0-9_-]{1,160}$/.test(id)) {
      throw error("Invalid evidence identity.");
    }
    const snap = await transaction.get(db.doc(`deliveryEvidence/${id}`));
    const record = await validateRecord(snap.exists ? snap.data() : null, {
      deliveryId,
      riderId,
      requiredStage,
    });
    return {id, record, fresh: false};
  }
  if (evidence.photoUrl) {
    const path = await verifyDeliveryEvidence({
      photoUrl: evidence.photoUrl,
      deliveryId,
      riderId,
      stage: requiredStage,
    });
    const [metadata] = await getStorage().bucket().file(path).getMetadata();
    const id = `ev_${crypto.createHash("sha256").update(`${path}:${metadata.generation}:${riderId}`).digest("hex")}`;
    const existing = await transaction.get(db.doc(`deliveryEvidence/${id}`));
    return {
      id,
      fresh: !existing.exists,
      record: {
        evidenceId: id,
        deliveryId,
        riderId,
        uploadedBy: riderId,
        stage: requiredStage,
        status: "verified",
        verified: true,
        immutable: true,
        storagePath: path,
        generation: text(metadata.generation),
        contentType: metadata.contentType,
        size: Number(metadata.size),
      },
    };
  }
  return null;
}
function writeVerified({db, transaction, resolved, deliveryId, riderId}) {
  if (!resolved) return;
  if (resolved.fresh) {
    transaction.create(db.doc(`deliveryEvidence/${resolved.id}`), {
      ...resolved.record,
      createdAt: FieldValue.serverTimestamp(),
    });
    transaction.set(
      db.doc(`deliveryEvidence/${deliveryId}/photos/${resolved.id}`),
      {...resolved.record, verified: true, immutable: true},
    );
    transaction.set(
      db.doc(`deliveryEvidence/${deliveryId}`),
      {
        deliveryId,
        verifiedPhotoCount: FieldValue.increment(1),
        latestPhotoPath: resolved.record.storagePath,
        latestRiderId: riderId,
        updatedAt: FieldValue.serverTimestamp(),
      },
      {merge: true},
    );
  }
}
async function completionProof({
  db,
  transaction,
  deliveryId,
  riderId,
  resolved,
}) {
  if (resolved) {
    return validateRecord(resolved.record, {
      deliveryId,
      riderId,
      requiredStage: "handover",
    });
  }
  const summary = await transaction.get(
    db.doc(`deliveryEvidence/${deliveryId}`),
  );
  if (!summary.exists || Number(summary.data().verifiedPhotoCount || 0) < 1) {
    throw error("Verified deliveryEvidence is required before completion.");
  }
  const photos = await transaction.get(
    db
      .collection(`deliveryEvidence/${deliveryId}/photos`)
      .where("verified", "==", true)
      .limit(20),
  );
  for (const doc of photos.docs) {
    try {
      return await validateRecord(doc.data(), {
        deliveryId,
        riderId,
        requiredStage: "handover",
      });
    } catch (_) {
      /* Other riders' or missing legacy objects are not completion proof. */
    }
  }
  throw error("No valid owned delivery evidence is available for completion.");
}
async function upload(data, context) {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Sign in to upload evidence.",
    );
  }
  const db = getFirestore();
  const uid = context.auth.uid;
  let deliveryId = text(data.deliveryId || data.requestId);
  const evidenceStage = stage(
    data.stage ||
      (data.action === "verify_collection_pin" ?
        "pickup" :
        data.action === "verify_receiver_pin" ?
          "handover" :
          ""),
  );
  if (
    !deliveryId ||
    !["pickup", "handover", "discrepancy"].includes(evidenceStage)
  ) {
    throw error("A valid delivery and evidence stage are required.");
  }
  let deliveryRef = db.doc(`deliveryRequests/${deliveryId}`);
  let initial = await deliveryRef.get();
  if (!initial.exists) {
    const found = await db
      .collection("deliveryRequests")
      .where("requestId", "==", deliveryId)
      .limit(1)
      .get();
    if (found.empty) throw error("Delivery not found.");
    initial = found.docs[0];
    deliveryRef = initial.ref;
    deliveryId = initial.id;
  }
  if (!owns(initial.data(), uid) || terminal(initial.data())) {
    throw error(
      "Only the assigned Rider can add evidence to an open delivery.",
    );
  }
  const {bytes, contentType} = decodeImage(data);
  const id = `ev_${crypto.createHash("sha256").update(`${deliveryId}:${uid}:${evidenceStage}:`).update(bytes).digest("hex")}`;
  const extension = contentType.split("/")[1].replace("jpeg", "jpg");
  const storagePath = `deliveryEvidence/${deliveryId}/${uid}/${id}.${extension}`;
  const file = getStorage().bucket().file(storagePath);
  try {
    await file.save(bytes, {
      resumable: false,
      preconditionOpts: {ifGenerationMatch: 0},
      metadata: {
        contentType,
        cacheControl: "private,no-store",
        metadata: {
          deliveryId,
          riderId: uid,
          evidenceId: id,
          stage: evidenceStage,
        },
      },
    });
  } catch (e) {
    if (e.code !== 412) throw e;
  }
  const [metadata] = await file.getMetadata();
  const record = await validateRecord(
    {
      evidenceId: id,
      deliveryId,
      riderId: uid,
      stage: evidenceStage,
      status: "verified",
      verified: true,
      immutable: true,
      storagePath,
      generation: text(metadata.generation),
      contentType,
    },
    {deliveryId, riderId: uid, requiredStage: evidenceStage},
  );
  await db.runTransaction(async (transaction) => {
    const [current, previous] = await Promise.all([
      transaction.get(deliveryRef),
      transaction.get(db.doc(`deliveryEvidence/${id}`)),
    ]);
    if (
      !current.exists ||
      !owns(current.data(), uid) ||
      terminal(current.data())
    ) {
      throw error("Delivery assignment or lifecycle changed during upload.");
    }
    writeVerified({
      db,
      transaction,
      resolved: {
        id,
        record: {
          ...record,
          visibility:
            evidenceStage === "handover" ? "sender_safe" : "rider_admin",
        },
        fresh: !previous.exists,
      },
      deliveryId,
      riderId: uid,
    });
  });
  return {
    success: true,
    evidenceId: id,
    deliveryId,
    stage: evidenceStage,
    status: "verified",
    contentType,
  };
}
exports.recordDeliveryEvidence = riderCallable(upload);
exports.submitDeliveryEvidence = riderCallable(async (data, context) => {
  if (!context.app) throw error("Security verification is required.");
  return upload(data, context);
});
exports._private = {
  decodeImage,
  validateRecord,
  resolve,
  writeVerified,
  completionProof,
  upload,
};
