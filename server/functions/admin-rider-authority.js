/* eslint-disable max-len, require-jsdoc */
const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {getStorage} = require("firebase-admin/storage");
const {requireAdmin} = require("./admin-auth");

const RIDER_ACTIONS = new Set([
  "approve",
  "reject",
  "suspend",
  "reactivate",
  "request_more_information",
  "review_document",
  "remove_profile_photo",
  "set_eligibility",
]);

const STATUS_ACTIONS = new Set(["approve", "reject", "suspend", "reactivate"]);
const DOCUMENT_STATUSES = new Set(["approved", "rejected", "replacement_requested"]);
const ELIGIBILITY_STATES = new Set(["eligible", "ineligible", "under_review"]);

function text(value) {
  return `${value || ""}`.trim();
}

function lower(value) {
  return text(value).toLowerCase();
}

function roleValues(token = {}) {
  const roles = Array.isArray(token.roles) ? token.roles.map(lower) : [];
  return new Set([
    lower(token.role),
    lower(token.adminRole),
    ...roles,
  ].filter(Boolean));
}

function assertRiderAdmin(context) {
  const uid = requireAdmin(context, "Rider administrator access is required.");
  const roles = roleValues(context.auth.token || {});
  if (
    context.auth.token.superAdmin === true ||
    context.auth.token.super_admin === true ||
    roles.has("super_admin") ||
    roles.has("admin") ||
    roles.has("operations_admin") ||
    roles.has("driver_manager") ||
    roles.has("rider_manager")
  ) {
    return uid;
  }
  throw new functions.https.HttpsError(
      "permission-denied",
      "Rider manager access is required.",
  );
}

function requestIdFor(data, actorId) {
  return text(data.requestIdempotencyKey || data.idempotencyKey) ||
    `${actorId}:${text(data.riderId)}:${lower(data.action)}:${text(data.documentId)}:${lower(data.status || data.eligibilityState)}`;
}

function statusPatch(action, actor, reason) {
  const timestamp = FieldValue.serverTimestamp();
  const patch = {
    adminOperationUpdatedBy: actor.email || actor.uid,
    adminOperationUpdatedAt: timestamp,
    adminOperationReason: reason,
    riderAuthorityUpdatedBy: actor.uid,
    riderAuthorityUpdatedAt: timestamp,
    updatedAt: timestamp,
  };
  switch (action) {
    case "approve":
      return {
        ...patch,
        adminOperationStatus: "approved",
        approvalStatus: "approved",
        verificationStatus: "approved",
        driverStatus: "active",
        eligibilityState: "eligible",
        riderEligibilityState: "eligible",
        approvedAt: timestamp,
        approvedBy: actor.uid,
      };
    case "reject":
      return {
        ...patch,
        adminOperationStatus: "rejected",
        approvalStatus: "rejected",
        verificationStatus: "rejected",
        driverStatus: "rejected",
        eligibilityState: "ineligible",
        riderEligibilityState: "ineligible",
        rejectedAt: timestamp,
        rejectedBy: actor.uid,
        rejectionReason: reason,
      };
    case "suspend":
      return {
        ...patch,
        adminOperationStatus: "suspended",
        driverStatus: "suspended",
        eligibilityState: "ineligible",
        riderEligibilityState: "ineligible",
        suspendedAt: timestamp,
        suspendedBy: actor.uid,
        suspensionReason: reason,
      };
    case "reactivate":
      return {
        ...patch,
        adminOperationStatus: "reactivated",
        approvalStatus: "approved",
        verificationStatus: "approved",
        driverStatus: "active",
        eligibilityState: "eligible",
        riderEligibilityState: "eligible",
        reactivatedAt: timestamp,
        reactivatedBy: actor.uid,
      };
    default:
      throw new functions.https.HttpsError("invalid-argument", "Unsupported Rider status action.");
  }
}

function informationPatch(actor, reason) {
  const timestamp = FieldValue.serverTimestamp();
  return {
    approvalStatus: "more_information_requested",
    verificationStatus: "more_information_requested",
    adminReviewStatus: "more_information_requested",
    informationRequestedAt: timestamp,
    informationRequestedBy: actor.uid,
    informationRequestedByEmail: actor.email || null,
    informationRequestNote: reason,
    riderAuthorityUpdatedBy: actor.uid,
    riderAuthorityUpdatedAt: timestamp,
    updatedAt: timestamp,
  };
}

function documentPatch(status, actor, reason, previous) {
  const timestamp = FieldValue.serverTimestamp();
  return {
    status,
    verificationStatus: status,
    reviewedAt: timestamp,
    reviewTimestamp: timestamp,
    reviewedBy: actor.uid,
    reviewer: actor.email || actor.uid,
    riderAuthorityUpdatedBy: actor.uid,
    riderAuthorityUpdatedAt: timestamp,
    ...(status === "approved" ? {active: true} : {}),
    ...(status === "approved" ? {rejectionReason: FieldValue.delete()} : {}),
    ...(status !== "approved" ? {rejectionReason: reason} : {}),
    reviewNotes: reason,
    statusHistory: FieldValue.arrayUnion([{
      previousStatus: previous,
      status,
      timestamp: new Date().toISOString(),
      reviewer: actor.uid,
      reviewerEmail: actor.email || null,
    }]),
    updatedAt: timestamp,
  };
}

function photoRemovalPatch(actor) {
  const timestamp = FieldValue.serverTimestamp();
  return {
    photoURL: FieldValue.delete(),
    photoUrl: FieldValue.delete(),
    photoPath: FieldValue.delete(),
    profilePhotoUrl: FieldValue.delete(),
    profileThumbnailUrl: FieldValue.delete(),
    profilePhotoPath: FieldValue.delete(),
    profileThumbnailPath: FieldValue.delete(),
    profilePhotoMetadata: FieldValue.delete(),
    profilePhotoVersion: FieldValue.increment(1),
    photoRemovedAt: timestamp,
    photoRemovedBy: actor.uid,
    riderAuthorityUpdatedBy: actor.uid,
    riderAuthorityUpdatedAt: timestamp,
    updatedAt: timestamp,
  };
}

function eligibilityPatch(state, actor, reason) {
  const timestamp = FieldValue.serverTimestamp();
  return {
    eligibilityState: state,
    riderEligibilityState: state,
    dispatchEligible: state === "eligible",
    eligibilityReviewedAt: timestamp,
    eligibilityReviewedBy: actor.uid,
    eligibilityReason: reason,
    riderAuthorityUpdatedBy: actor.uid,
    riderAuthorityUpdatedAt: timestamp,
    updatedAt: timestamp,
  };
}

async function deleteStorageObject(path) {
  const cleanPath = text(path);
  if (!cleanPath) return;
  try {
    await getStorage().bucket().file(cleanPath).delete({ignoreNotFound: true});
  } catch (error) {
    console.warn("rider_authority_storage_delete_failed", {
      path: cleanPath,
      message: error && error.message,
    });
  }
}

exports.adminReviewRider = functions.https.onCall(async (data, context) => {
  const actorId = assertRiderAdmin(context);
  const db = getFirestore();
  const riderId = text(data && data.riderId);
  const action = lower(data && data.action);
  const reason = text(data && data.reason);
  const documentId = text(data && data.documentId);
  const documentStatus = lower(data && data.documentStatus);
  const eligibilityState = lower(data && data.eligibilityState);
  const idempotencyKey = requestIdFor(data || {}, actorId);

  if (!riderId || !RIDER_ACTIONS.has(action)) {
    throw new functions.https.HttpsError("invalid-argument", "A Rider and supported action are required.");
  }
  if (!reason) {
    throw new functions.https.HttpsError("invalid-argument", "A Rider authority reason is required.");
  }

  const actor = {
    uid: actorId,
    email: text(context.auth.token.email),
  };
  const riderRef = db.collection("riders").doc(riderId);
  const profileRef = db.collection("riderProfiles").doc(riderId);
  const auditRef = db.collection("riderAuthorityAudit").doc(idempotencyKey);
  const result = await db.runTransaction(async (transaction) => {
    const auditSnap = await transaction.get(auditRef);
    if (auditSnap.exists) {
      return {idempotent: true, auditId: auditRef.id, ...(auditSnap.data() || {})};
    }
    const [riderSnap, profileSnap] = await Promise.all([
      transaction.get(riderRef),
      transaction.get(profileRef),
    ]);
    if (!riderSnap.exists && !profileSnap.exists) {
      throw new functions.https.HttpsError("not-found", "Rider was not found.");
    }
    const rider = riderSnap.data() || {};
    const profile = profileSnap.data() || {};
    const before = {
      approvalStatus: profile.approvalStatus || rider.approvalStatus || null,
      verificationStatus: profile.verificationStatus || rider.verificationStatus || null,
      driverStatus: profile.driverStatus || rider.driverStatus || null,
      eligibilityState: profile.eligibilityState || rider.eligibilityState || null,
    };
    let patch = null;
    let documentPatchValue = null;
    let eventAction = action;
    if (STATUS_ACTIONS.has(action)) {
      patch = statusPatch(action, actor, reason);
    } else if (action === "request_more_information") {
      patch = informationPatch(actor, reason);
      eventAction = "more_information_requested";
    } else if (action === "review_document") {
      if (!documentId || !DOCUMENT_STATUSES.has(documentStatus)) {
        throw new functions.https.HttpsError("invalid-argument", "Document id and supported status are required.");
      }
      const docRef = db.collection("riderDocuments").doc(documentId);
      const docSnap = await transaction.get(docRef);
      if (!docSnap.exists) {
        throw new functions.https.HttpsError("not-found", "Rider document was not found.");
      }
      const doc = docSnap.data() || {};
      const docRiderId = text(doc.riderId || doc.driverId || doc.uid);
      if (docRiderId !== riderId) {
        throw new functions.https.HttpsError("permission-denied", "Document does not belong to this Rider.");
      }
      const previous = text(doc.status || doc.verificationStatus || "missing");
      documentPatchValue = documentPatch(documentStatus, actor, reason, previous);
      transaction.set(docRef, documentPatchValue, {merge: true});
      eventAction = documentStatus === "approved" ? "document_approved" :
        documentStatus === "rejected" ? "document_rejected" :
        "document_replacement_requested";
    } else if (action === "remove_profile_photo") {
      patch = photoRemovalPatch(actor);
      eventAction = "profile_photo_removed";
    } else if (action === "set_eligibility") {
      if (!ELIGIBILITY_STATES.has(eligibilityState)) {
        throw new functions.https.HttpsError("invalid-argument", "Supported eligibility state is required.");
      }
      patch = eligibilityPatch(eligibilityState, actor, reason);
      eventAction = `eligibility_${eligibilityState}`;
    }
    if (patch) {
      transaction.set(riderRef, patch, {merge: true});
      transaction.set(profileRef, patch, {merge: true});
    }
    const audit = {
      riderId,
      action,
      eventAction,
      documentId: documentId || null,
      reason,
      before,
      patchKeys: patch ? Object.keys(patch) : Object.keys(documentPatchValue || {}),
      actorId,
      actorEmail: actor.email || null,
      createdAt: FieldValue.serverTimestamp(),
    };
    transaction.set(auditRef, audit);
    return {idempotent: false, auditId: auditRef.id, eventAction, before};
  });

  if (action === "remove_profile_photo") {
    const profilePath = text(data.profilePhotoPath || data.photoPath ||
      `rider-profiles/${riderId}/profile.jpg`);
    const thumbnailPath = text(data.profileThumbnailPath ||
      `rider-profiles/${riderId}/thumbnail.jpg`);
    await Promise.all([
      deleteStorageObject(profilePath),
      deleteStorageObject(thumbnailPath),
    ]);
  }

  await db.collection("notifications").add({
    userId: riderId,
    riderId,
    audience: "rider",
    type: "rider_authority",
    action,
    status: result.eventAction || action,
    title: "Rider account update",
    body: reason,
    read: false,
    createdAt: FieldValue.serverTimestamp(),
  });

  return {
    riderId,
    action,
    status: result.eventAction || action,
    auditId: result.auditId,
    idempotent: result.idempotent === true,
  };
});
