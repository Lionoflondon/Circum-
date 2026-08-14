/* eslint-disable max-len, require-jsdoc */
const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {getStorage} = require("firebase-admin/storage");
const {requireAdmin} = require("./admin-auth");

const ALLOWED_TYPES = new Set(["image/jpeg", "image/png", "image/webp"]);
const MAX_BYTES = 10 * 1024 * 1024;

function text(value) {
  return `${value || ""}`.trim();
}

function lower(value) {
  return text(value).toLowerCase();
}

function requireIrisAdmin(context) {
  const token = context.auth && context.auth.token ? context.auth.token : {};
  const roles = Array.isArray(token.roles) ? token.roles.map(lower) : [];
  const allowed = token.admin === true || token.superAdmin === true ||
    token.super_admin === true ||
    [lower(token.adminRole), lower(token.role), ...roles]
        .some((role) => ["admin", "super_admin", "operations_admin"].includes(role));
  if (!allowed) {
    throw new functions.https.HttpsError("permission-denied", "IRIS administrator access is required.");
  }
}

function identifiers(data) {
  const itemId = text(data && data.itemId);
  const storagePath = text(data && data.storagePath);
  if (!itemId || !/^[A-Za-z0-9_-]{1,160}$/.test(itemId)) {
    throw new functions.https.HttpsError("invalid-argument", "A valid itemId is required.");
  }
  if (storagePath && !storagePath.startsWith(`irisReferenceImages/${itemId}/`)) {
    throw new functions.https.HttpsError("invalid-argument", "The reference image path does not match the IRIS item.");
  }
  return {itemId, storagePath};
}

async function signedPreview(storagePath) {
  const [url] = await getStorage().bucket().file(storagePath).getSignedUrl({
    version: "v4",
    action: "read",
    expires: Date.now() + 15 * 60 * 1000,
  });
  return url;
}

exports.getIrisReferenceImage = functions.runWith({enforceAppCheck: true}).https.onCall(async (data, context) => {
  requireAdmin(context, "IRIS administrator access is required.");
  requireIrisAdmin(context);
  const {itemId} = identifiers(data);
  const snapshot = await getFirestore().collection("irisReferenceImages").doc(itemId).get();
  if (!snapshot.exists || snapshot.data().deleted === true) {
    return {exists: false, itemId};
  }
  const record = snapshot.data();
  return {
    exists: true,
    itemId,
    fileName: record.fileName || null,
    contentType: record.contentType || null,
    size: record.size || null,
    uploadedAt: record.uploadedAt || null,
    updatedAt: record.updatedAt || null,
    previewUrl: await signedPreview(record.storagePath),
  };
});

exports.finalizeIrisReferenceImage = functions.runWith({enforceAppCheck: true}).https.onCall(async (data, context) => {
  const adminId = requireAdmin(context, "IRIS administrator access is required.");
  requireIrisAdmin(context);
  const {itemId, storagePath} = identifiers(data);
  if (!storagePath) {
    throw new functions.https.HttpsError("invalid-argument", "storagePath is required.");
  }
  const file = getStorage().bucket().file(storagePath);
  const [metadata] = await file.getMetadata().catch(() => {
    throw new functions.https.HttpsError("not-found", "The uploaded reference image was not found.");
  });
  const contentType = text(metadata.contentType).toLowerCase();
  const size = Number(metadata.size || 0);
  if (!ALLOWED_TYPES.has(contentType) || size <= 0 || size > MAX_BYTES) {
    await file.delete({ignoreNotFound: true}).catch(() => null);
    throw new functions.https.HttpsError("invalid-argument", "Use a JPG, PNG, or WebP image no larger than 10 MB.");
  }

  const db = getFirestore();
  const reference = db.collection("irisReferenceImages").doc(itemId);
  let previousPath = "";
  let action = "iris_reference_image_uploaded";
  await db.runTransaction(async (transaction) => {
    const existing = await transaction.get(reference);
    const previous = existing.exists ? existing.data() : {};
    previousPath = text(previous.storagePath);
    if (previousPath && previous.deleted !== true && previousPath !== storagePath) {
      action = "iris_reference_image_replaced";
    }
    const generation = text(metadata.generation) || `${Date.now()}`;
    transaction.set(reference, {
      itemId,
      storagePath,
      fileName: storagePath.split("/").pop(),
      contentType,
      size,
      generation,
      deleted: false,
      uploadedBy: adminId,
      uploadedAt: previousPath ? previous.uploadedAt || FieldValue.serverTimestamp() : FieldValue.serverTimestamp(),
      updatedBy: adminId,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    transaction.set(db.collection("adminAuditLogs").doc(`iris_reference_${itemId}_${generation}`), {
      adminUserId: adminId,
      actionType: action,
      recordType: "irisReferenceImages",
      recordId: itemId,
      previousStoragePath: previousPath || null,
      storagePath,
      contentType,
      size,
      createdAt: FieldValue.serverTimestamp(),
    });
  });
  if (previousPath && previousPath !== storagePath) {
    await getStorage().bucket().file(previousPath).delete({ignoreNotFound: true}).catch(() => null);
  }
  return {success: true, itemId, action, previewUrl: await signedPreview(storagePath)};
});

exports.deleteIrisReferenceImage = functions.runWith({enforceAppCheck: true}).https.onCall(async (data, context) => {
  const adminId = requireAdmin(context, "IRIS administrator access is required.");
  requireIrisAdmin(context);
  const {itemId} = identifiers(data);
  const db = getFirestore();
  const reference = db.collection("irisReferenceImages").doc(itemId);
  const snapshot = await reference.get();
  if (!snapshot.exists || snapshot.data().deleted === true) {
    return {success: true, duplicate: true, itemId};
  }
  const record = snapshot.data();
  await getStorage().bucket().file(record.storagePath).delete({ignoreNotFound: true});
  const batch = db.batch();
  batch.set(reference, {
    deleted: true,
    deletedBy: adminId,
    deletedAt: FieldValue.serverTimestamp(),
    updatedBy: adminId,
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  batch.set(db.collection("adminAuditLogs").doc(`iris_reference_delete_${itemId}_${text(record.generation) || "legacy"}`), {
    adminUserId: adminId,
    actionType: "iris_reference_image_deleted",
    recordType: "irisReferenceImages",
    recordId: itemId,
    previousStoragePath: record.storagePath,
    createdAt: FieldValue.serverTimestamp(),
  });
  await batch.commit();
  return {success: true, duplicate: false, itemId};
});
