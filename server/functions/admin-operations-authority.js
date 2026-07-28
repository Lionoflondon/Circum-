/* eslint-disable max-len, require-jsdoc */
const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue, Timestamp} = require("firebase-admin/firestore");

const ADMIN_ROLES = new Set([
  "admin",
  "super_admin",
  "operations_admin",
  "support_agent",
  "finance_admin",
  "driver_manager",
]);
const MANAGE_ADMIN_ROLES = new Set(["admin", "super_admin"]);

function clean(value) {
  return `${value || ""}`.trim();
}

function lower(value) {
  return clean(value).toLowerCase();
}

function tokenRoles(token = {}) {
  const roles = Array.isArray(token.roles) ? token.roles.map(lower) : [];
  return new Set([
    lower(token.role),
    lower(token.adminRole),
    ...roles,
    token.admin === true ? "admin" : "",
    token.superAdmin === true || token.super_admin === true ? "super_admin" : "",
  ].filter(Boolean));
}

function activeRolesFromRecord(record = {}) {
  if (!record || lower(record.status || "active") === "inactive") return [];
  const roles = [
    record.role,
    record.adminRole,
    ...(Array.isArray(record.roles) ? record.roles : []),
  ].map(lower).filter(Boolean);
  return roles.length ? roles : [];
}

async function resolveActor(context) {
  if (!context || !context.auth || !context.auth.uid) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in first.");
  }
  const db = getFirestore();
  const uid = context.auth.uid;
  const email = lower(context.auth.token && context.auth.token.email);
  const uidDoc = await db.collection("adminUsers").doc(uid).get();
  const emailDoc = email ? await db.collection("adminUsers").doc(email).get() : null;
  const docRecords = [
    uidDoc.exists ? uidDoc.data() : null,
    emailDoc && emailDoc.exists ? emailDoc.data() : null,
  ].filter(Boolean);
  const roles = new Set([
    ...tokenRoles(context.auth.token || {}),
    ...docRecords.flatMap(activeRolesFromRecord),
  ]);
  if (![...roles].some((role) => ADMIN_ROLES.has(role))) {
    throw new functions.https.HttpsError("permission-denied", "Administrator access is required.");
  }
  return {
    uid,
    email,
    roles: [...roles],
    canManageAdmins: [...roles].some((role) => MANAGE_ADMIN_ROLES.has(role)),
    label: email || uid,
  };
}

function requireManageAdmins(actor) {
  if (!actor.canManageAdmins) {
    throw new functions.https.HttpsError("permission-denied", "Admin user management access is required.");
  }
}

function requireAnyRole(actor, allowed, message) {
  const roles = new Set((actor.roles || []).map(lower));
  if (!allowed.some((role) => roles.has(role))) {
    throw new functions.https.HttpsError("permission-denied", message);
  }
}

function requireOperations(actor, message = "Operations Admin access is required.") {
  requireAnyRole(actor, ["admin", "super_admin", "operations_admin"], message);
}

function requireSupport(actor, message = "Support Admin access is required.") {
  requireAnyRole(actor, ["admin", "super_admin", "operations_admin", "support_agent"], message);
}

function requireFinance(actor, message = "Finance Admin access is required.") {
  requireAnyRole(actor, ["admin", "super_admin", "finance_admin"], message);
}

function auditPayload(actor, data, before, after) {
  return {
    adminUserId: actor.uid,
    actorId: actor.uid,
    actorEmail: actor.email || null,
    actionType: clean(data.actionType || data.action),
    recordType: clean(data.recordType || data.collection),
    recordId: clean(data.recordId || data.targetId),
    oldValue: before || {},
    newValue: after || {},
    reason: clean(data.reason),
    source: "circum_admin_authority",
    createdAt: FieldValue.serverTimestamp(),
  };
}

async function writeAudit(db, actor, data, before, after) {
  const ref = await db.collection("adminAuditLogs").add(auditPayload(actor, data, before, after));
  return ref.id;
}

function operationStatusPatch(status, actor, reason) {
  const timestamp = FieldValue.serverTimestamp();
  return {
    adminOperationStatus: status,
    adminOperationReason: reason,
    adminOperationUpdatedBy: actor.label,
    adminOperationUpdatedAt: timestamp,
    ...(status === "paused" ? {adminPaused: true} : {}),
    ...(status === "resumed" ? {adminPaused: false} : {}),
    ...(status === "escalated" ? {escalationStatus: "open"} : {}),
    ...(status === "waiting_review" ? {waitingReviewStatus: "open"} : {}),
    ...(status === "no_show_review" ? {noShowReviewStatus: "open"} : {}),
    ...(status === "vanguard_custody_flagged" ? {vanguardCustodyReviewStatus: "concern_flagged"} : {}),
    ...(status === "vanguard_custody_escalated" ? {vanguardCustodyReviewStatus: "escalated"} : {}),
    ...(status === "vanguard_evidence_requested" ? {vanguardCustodyEvidenceStatus: "requested"} : {}),
    ...(status === "vanguard_custody_reopened" ? {vanguardCustodyReviewStatus: "open"} : {}),
    ...(status === "vanguard_custody_closed" ? {vanguardCustodyReviewStatus: "closed"} : {}),
    ...(status === "vanguard_reviewer_assigned" ? {vanguardCustodyReviewerStatus: "assigned"} : {}),
    ...(status === "iris_review_override" ? {irisReviewStatus: "admin_review"} : {}),
    ...(status === "fraud_flagged" ? {fraudReviewStatus: "flagged"} : {}),
    updatedAt: timestamp,
  };
}

function irisReviewPatch(status, actor, reason) {
  const timestamp = FieldValue.serverTimestamp();
  return {
    irisReviewStatus: status,
    irisReviewedBy: actor.label,
    irisReviewedAt: timestamp,
    irisReviewReason: reason,
    ...(status === "learning_flagged" ? {irisLearningQueueStatus: "pending"} : {}),
    ...(status === "learning_promoted" ? {irisLearningQueueStatus: "promoted"} : {}),
    ...(status === "learning_rejected" ? {irisLearningQueueStatus: "rejected"} : {}),
    ...(status === "engineering_review" ? {engineeringReviewStatus: "open"} : {}),
    ...(status === "more_evidence_requested" ? {evidenceRequestStatus: "requested"} : {}),
    ...(status === "evidence_approved" ? {evidenceReviewStatus: "approved"} : {}),
    ...(status === "evidence_rejected" ? {evidenceReviewStatus: "rejected"} : {}),
    ...(status === "evidence_archived" ? {evidenceReviewStatus: "archived"} : {}),
    ...(status === "review_assigned" ? {irisAssignmentStatus: "assigned"} : {}),
    ...(status === "duplicate_merge_review" ? {irisMergeReviewStatus: "open"} : {}),
    ...(status === "archived_review_restored" ? {irisReviewArchived: false} : {}),
    ...(status === "closed" ? {irisReviewClosed: true} : {}),
    updatedAt: timestamp,
  };
}

function senderAccountPatch(status, actor, reason) {
  const timestamp = FieldValue.serverTimestamp();
  return {
    accountStatus: status,
    status: status === "reactivated" ? "active" : status,
    adminStatusUpdatedBy: actor.label,
    adminStatusUpdatedAt: timestamp,
    ...(reason ? {adminStatusReason: reason} : {}),
    ...(status === "closure_review" ? {closureReviewStatus: "requested"} : {}),
    updatedAt: timestamp,
  };
}

function businessStatusPatch(status, actor) {
  const timestamp = FieldValue.serverTimestamp();
  const approved = status === "approved" || status === "reactivated";
  const canonicalStatus = status === "reactivated" ? "approved" : status;
  return {
    status: canonicalStatus,
    approvalStatus: canonicalStatus,
    businessStatus: canonicalStatus,
    verificationStatus: approved ? "approved" : canonicalStatus,
    isApproved: approved,
    adminStatusUpdatedBy: actor.label,
    adminStatusUpdatedAt: timestamp,
    updatedAt: timestamp,
  };
}

function businessOperationPatch(status, actor, reason) {
  const timestamp = FieldValue.serverTimestamp();
  return {
    businessOperationStatus: status,
    businessOperationReason: reason,
    businessOperationUpdatedBy: actor.label,
    businessOperationUpdatedAt: timestamp,
    ...(status === "verified" ? {verificationStatus: "approved", status: "approved"} : {}),
    ...(status === "manager_assigned" ? {managerAssignmentStatus: "assigned"} : {}),
    ...(status.includes("invoice") ? {invoiceReviewStatus: status} : {}),
    ...(status.includes("subscription") ? {subscriptionReviewStatus: status} : {}),
    ...(status.includes("roth") ? {rothReviewStatus: status} : {}),
    updatedAt: timestamp,
  };
}

function healthStatusPatch(status, actor, reason) {
  const timestamp = FieldValue.serverTimestamp();
  return {
    status,
    adminUpdatedBy: actor.label,
    adminReason: reason,
    ...(status === "pharmacy_assigned" || status === "pharmacy_reassigned" ? {pharmacyReviewStatus: status} : {}),
    ...(status === "rider_assigned" ? {riderAssignmentStatus: "assigned"} : {}),
    ...(status === "escalated" ? {escalationStatus: "open"} : {}),
    ...(status === "review_approved" ? {clinicalReviewStatus: "approved"} : {}),
    ...(status === "review_rejected" ? {clinicalReviewStatus: "rejected"} : {}),
    ...(status === "evidence_requested" ? {clinicalEvidenceStatus: "requested"} : {}),
    ...(status === "paused" ? {adminPaused: true} : {}),
    ...(status === "resumed" ? {adminPaused: false} : {}),
    ...(status === "closed" ? {caseStatus: "closed"} : {}),
    adminUpdatedAt: timestamp,
    updatedAt: timestamp,
  };
}

function financePatch(status, actor) {
  const timestamp = FieldValue.serverTimestamp();
  return {
    financeReviewStatus: status,
    financeReviewedBy: actor.label,
    financeReviewedAt: timestamp,
    financeEscalated: status === "escalated",
    ...(status.includes("refund") ? {refundReviewStatus: status} : {}),
    ...(status.includes("investigation") ? {investigationStatus: status} : {}),
    ...(status.includes("wallet") ? {walletReviewStatus: status} : {}),
    ...(status.includes("roth") ? {rothReviewStatus: status} : {}),
    updatedAt: timestamp,
  };
}

const GIFT_WORKFLOW_STATUSES = new Set([
  "approved",
  "rejected",
  "assigned",
  "reassigned",
  "escalated",
  "paused",
  "resumed",
  "closed",
  "information_requested",
]);

const GIFT_BRAND_STATUSES = new Set([
  "approved",
  "pending",
  "paused",
  "suspended",
  "inactive",
  "history_reviewed",
]);

function giftWorkflowPatch(status, actor, reason) {
  if (!GIFT_WORKFLOW_STATUSES.has(status)) {
    throw new functions.https.HttpsError("invalid-argument", "Unsupported gift workflow status.");
  }
  if (!reason) {
    throw new functions.https.HttpsError("invalid-argument", "A gift workflow reason is required.");
  }
  const timestamp = FieldValue.serverTimestamp();
  return {
    giftAdminStatus: status,
    giftReviewedBy: actor.label,
    giftReviewedAt: timestamp,
    giftReviewReason: reason,
    giftEscalated: status === "escalated",
    giftPaused: status === "paused",
    giftClosed: status === "closed",
    ...(status === "information_requested" ? {informationRequestStatus: "requested"} : {}),
    ...(status === "approved" ? {moderationState: "approved"} : {}),
    ...(status === "rejected" ? {moderationState: "rejected"} : {}),
    updatedAt: timestamp,
  };
}

function giftCampaignParticipantPatch(status, actor) {
  if (!GIFT_WORKFLOW_STATUSES.has(status) && !["assign_later", "exported"].includes(status)) {
    throw new functions.https.HttpsError("invalid-argument", "Unsupported gift campaign status.");
  }
  const timestamp = FieldValue.serverTimestamp();
  return {
    ...(status !== "exported" ? {matchStatus: status, adminReviewStatus: status} : {}),
    ...(status === "assign_later" ? {assignmentDeferredAt: timestamp, assignmentDeferredBy: actor.uid} : {}),
    ...(status === "rejected" ? {
      suggestedParticipantId: FieldValue.delete(),
      suggestedMatchScore: FieldValue.delete(),
      suggestedMatchReason: FieldValue.delete(),
    } : {}),
    ...(status === "exported" ? {lastExportedAt: timestamp, lastExportedBy: actor.label} : {}),
    updatedAt: timestamp,
  };
}

function giftRequestForCampaign(sender, recipient, campaign, matchId) {
  return {
    senderId: sender.userId || null,
    senderName: sender.displayName || null,
    recipientName: recipient.displayName || null,
    giftMode: "anonymous_gift",
    anonymousGiftType: "campaign",
    senderRevealMode: "anonymous_until_consent",
    senderRevealConsent: "not_requested",
    recipientRevealRequestStatus: "none",
    campaignId: campaign.campaignId || null,
    campaignName: campaign.campaignName || "Bringing London Closer",
    campaignTagline: campaign.campaignTagline || "100 Londoners. 100 gifts. 100 stories.",
    campaignType: "anonymous_gifting",
    matchId,
    status: "draft",
    budgetStatus: "pending_allocation",
    recipientContentConsent: "pending",
    senderContentConsent: "pending",
    allowCircumSocialUse: false,
    allowBrandTagging: false,
    allowReactionRecording: false,
    allowPublicPosting: false,
    allowAnonymousPosting: false,
    contentUsageScope: "private",
    anonymousByDefault: true,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
}

function giftBrandPatch(data, actor) {
  const status = lower(data.status || "pending");
  if (!GIFT_BRAND_STATUSES.has(status)) {
    throw new functions.https.HttpsError("invalid-argument", "Unsupported brand partner status.");
  }
  const timestamp = FieldValue.serverTimestamp();
  const active = status === "approved";
  const cleanList = Array.isArray(data.approvedFor) ?
    data.approvedFor.map(clean).filter(Boolean).slice(0, 50) : [];
  return {
    ...(data.partnerName !== undefined ? {partnerName: clean(data.partnerName)} : {}),
    ...(data.brandName !== undefined ? {brandName: clean(data.brandName)} : {}),
    ...(data.category !== undefined ? {category: clean(data.category)} : {}),
    ...(data.contactName !== undefined ? {contactName: clean(data.contactName)} : {}),
    ...(data.contactEmail !== undefined ? {contactEmail: lower(data.contactEmail)} : {}),
    ...(data.phone !== undefined ? {phone: clean(data.phone)} : {}),
    ...(data.website !== undefined ? {website: clean(data.website)} : {}),
    ...(data.notes !== undefined ? {internalNotes: clean(data.notes)} : {}),
    ...(cleanList.length ? {approvedFor: cleanList} : {}),
    ...(status !== "history_reviewed" ? {status, partnershipStatus: status, active} : {}),
    ...(status === "history_reviewed" ? {lastHistoryReviewedAt: timestamp, lastHistoryReviewedBy: actor.label} : {}),
    updatedAt: timestamp,
    updatedBy: actor.label,
    ...(status === "approved" ? {verifiedAt: timestamp, verifiedBy: actor.label} : {}),
    ...(status === "suspended" || status === "paused" ? {suspendedAt: timestamp, suspendedBy: actor.label} : {}),
    ...(status === "inactive" ? {deactivatedAt: timestamp, deactivatedBy: actor.label} : {}),
  };
}

function slugId(value) {
  return clean(value).toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-|-$/g, "")
      .slice(0, 160);
}

function allowedAdminPatch(data, allowed) {
  const patch = {};
  const source = data && typeof data === "object" ? data : {};
  for (const key of allowed) {
    if (Object.prototype.hasOwnProperty.call(source, key)) {
      patch[key] = source[key];
    }
  }
  return patch;
}

const IRIS_REPOSITORY_COLLECTIONS = new Set([
  "irisCanonicalObjects",
  "irisPolicies",
  "irisEvidence",
  "irisReferenceImages",
]);

const IRIS_CANDIDATE_COLLECTIONS = new Set([
  "irisLearningCases",
  "iris_learning_review_candidates",
]);

const IRIS_REPOSITORY_PATCH_FIELDS = [
  "canonicalId",
  "objectName",
  "canonicalName",
  "category",
  "subcategory",
  "knownWeight",
  "estimatedWeight",
  "irisEstimatedWeight",
  "weightBand",
  "vehicleRecommendation",
  "recommendedVehicle",
  "handlingRequirements",
  "handlingNotes",
  "notes",
  "status",
];

const GIFT_EDITOR_COLLECTIONS = new Set(["giftRequests", "giftOrders"]);
const PLATFORM_OPERATION_COLLECTIONS = new Set([
  "platformConfig",
  "platformStatus",
  "platformNotices",
  "platformVersions",
]);
const PLATFORM_OPERATION_STATUSES = new Set([
  "active",
  "inactive",
  "enabled",
  "disabled",
  "maintenance_enabled",
  "maintenance_disabled",
  "published",
  "unpublished",
  "acknowledged",
  "resolved",
]);

function stringList(value) {
  if (Array.isArray(value)) return value.map(clean).filter(Boolean).slice(0, 80);
  return clean(value).split(",").map(clean).filter(Boolean).slice(0, 80);
}

function giftRequestEditorPatch(data, actor) {
  const patch = {};
  const stringFields = [
    "status",
    "manualGiftPlan",
    "adminDecision",
    "internalNotes",
    "procurementItemTitle",
    "procurementSupplier",
    "procurementOrderReference",
    "procurementDeliveryEta",
    "procurementNotes",
    "giftStoryCircumMessage",
    "giftStoryCustomAudioUrl",
    "giftStorySharePrivacy",
    "contentUsageScope",
    "contentStatus",
    "captionDraft",
    "approvedCaption",
    "postedTikTokUrl",
    "postedInstagramUrl",
    "postedYouTubeShortsUrl",
  ];
  for (const field of stringFields) {
    if (Object.prototype.hasOwnProperty.call(data, field)) {
      patch[field] = clean(data[field]);
    }
  }
  if (Object.prototype.hasOwnProperty.call(data, "procurementEstimatedCost")) {
    const value = Number(data.procurementEstimatedCost);
    patch.procurementEstimatedCost = Number.isFinite(value) ? value : null;
  }
  if (Object.prototype.hasOwnProperty.call(data, "procurementActualCost")) {
    const value = Number(data.procurementActualCost);
    patch.procurementActualCost = Number.isFinite(value) ? value : null;
  }
  for (const field of ["giftStoryEnabled", "giftStoryApproved", "allowCircumSocialUse", "allowPublicPosting", "allowBrandTagging"]) {
    if (Object.prototype.hasOwnProperty.call(data, field)) patch[field] = data[field] === true;
  }
  if (Object.prototype.hasOwnProperty.call(data, "irisAcceptedSignals")) {
    patch["giftsTeamWorkspace.irisCollaboration.acceptedSignals"] = stringList(data.irisAcceptedSignals);
  }
  if (Object.prototype.hasOwnProperty.call(data, "rejectedIrisGiftSuggestionIds")) {
    patch.rejectedIrisGiftSuggestionIds = stringList(data.rejectedIrisGiftSuggestionIds);
  }
  if (Object.prototype.hasOwnProperty.call(data, "giftStoryPhotoUrls")) {
    const photos = stringList(data.giftStoryPhotoUrls);
    patch.giftStoryPhotoUrls = photos;
    patch.giftStoryPhotos = photos;
  }
  patch.giftWorkspaceAuditTrail = FieldValue.arrayUnion([{
    event: "gift_request_editor_saved",
    updatedBy: actor.label,
    updatedAt: new Date().toISOString(),
  }]);
  patch.updatedAt = FieldValue.serverTimestamp();
  patch.updatedBy = actor.label;
  return patch;
}

function platformOperationPatch(status, actor, reason) {
  if (!PLATFORM_OPERATION_STATUSES.has(status)) {
    throw new functions.https.HttpsError("invalid-argument", "Unsupported platform operation status.");
  }
  const trimmedReason = clean(reason);
  if (!trimmedReason) {
    throw new functions.https.HttpsError("invalid-argument", "A platform operation reason is required.");
  }
  return {
    adminOperationStatus: status,
    adminUpdatedBy: actor.label,
    adminUpdatedAt: FieldValue.serverTimestamp(),
    adminReason: trimmedReason,
    ...(status === "maintenance_enabled" ? {maintenanceMode: true} : {}),
    ...(status === "maintenance_disabled" ? {maintenanceMode: false} : {}),
    ...(status === "published" ? {published: true} : {}),
    ...(status === "unpublished" ? {published: false} : {}),
    ...(status === "enabled" ? {enabled: true} : {}),
    ...(status === "disabled" ? {enabled: false} : {}),
    ...(status === "resolved" ? {resolved: true} : {}),
  };
}

function duplicateDelivery(source, newId) {
  const copy = {...source};
  delete copy.historyId;
  delete copy.driverRatingId;
  delete copy.ratedAt;
  delete copy.proofOfDelivery;
  return {
    ...copy,
    requestId: newId,
    status: "requested",
    dispatchStatus: "requested",
    matchingStatus: "available",
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
    source: `${source.source || "circum"}-admin-duplicate`,
    adminDuplicatedFrom: source.requestId || source.id || null,
  };
}

exports.adminResolveAccess = functions.https.onCall(async (data, context) => {
  const actor = await resolveActor(context);
  const db = getFirestore();
  const patch = {lastLoginAt: FieldValue.serverTimestamp()};
  await Promise.all([
    db.collection("adminUsers").doc(actor.uid).set(patch, {merge: true}),
    actor.email ? db.collection("adminUsers").doc(actor.email).set(patch, {merge: true}) : null,
  ].filter(Boolean));
  return {roles: actor.roles};
});

exports.adminRecordAuditEntry = functions.https.onCall(async (data, context) => {
  const actor = await resolveActor(context);
  const db = getFirestore();
  const auditId = await writeAudit(db, actor, data || {}, data.oldValue || {}, data.newValue || {});
  return {ok: true, auditId};
});

exports.adminSaveAdminUser = functions.https.onCall(async (data, context) => {
  const actor = await resolveActor(context);
  requireManageAdmins(actor);
  const email = lower(data.email);
  const documentId = clean(data.documentId || email);
  if (!email || !email.includes("@") || !documentId) {
    throw new functions.https.HttpsError("invalid-argument", "A valid Admin email is required.");
  }
  const db = getFirestore();
  const ref = db.collection("adminUsers").doc(documentId);
  const snap = await ref.get();
  const before = snap.exists ? snap.data() : {};
  const patch = {
    email,
    role: clean(data.role || "operations_admin"),
    status: clean(data.status || "active"),
    roles: [clean(data.role || "operations_admin")],
    invitedBy: actor.label,
    updatedAt: FieldValue.serverTimestamp(),
    ...(snap.exists ? {} : {createdAt: FieldValue.serverTimestamp()}),
    ...(clean(data.adminNote) ? {adminNote: clean(data.adminNote)} : {}),
  };
  await ref.set(patch, {merge: true});
  await writeAudit(db, actor, {
    actionType: snap.exists ? "admin_user_edit" : "admin_user_invite",
    recordType: "adminUsers",
    recordId: documentId,
    reason: clean(data.reason || "Admin user updated from Admin."),
  }, before, patch);
  return {ok: true, documentId};
});

exports.adminDuplicateDelivery = functions.https.onCall(async (data, context) => {
  const actor = await resolveActor(context);
  requireOperations(actor);
  const id = clean(data.deliveryId);
  const newId = clean(data.newId) || `CIR-ADM-${Date.now()}`;
  if (!id) throw new functions.https.HttpsError("invalid-argument", "Delivery is required.");
  const db = getFirestore();
  const sourceSnap = await db.collection("deliveryRequests").doc(id).get();
  if (!sourceSnap.exists) throw new functions.https.HttpsError("not-found", "Delivery was not found.");
  const duplicate = duplicateDelivery({...sourceSnap.data(), id: sourceSnap.id}, newId);
  await db.collection("deliveryRequests").doc(newId).set(duplicate);
  await writeAudit(db, actor, {
    actionType: "delivery_duplicate",
    recordType: "deliveryRequests",
    recordId: newId,
    reason: clean(data.reason || "Admin duplicated delivery from operations console."),
  }, {requestId: id}, {requestId: newId});
  return {ok: true, deliveryId: newId};
});

exports.adminUpdateDeliveryOperation = functions.https.onCall(async (data, context) => {
  const actor = await resolveActor(context);
  requireOperations(actor);
  const id = clean(data.deliveryId);
  const status = lower(data.status);
  const reason = clean(data.reason || "Updated from Circum Admin Delivery Operations");
  if (!id || !status) throw new functions.https.HttpsError("invalid-argument", "Delivery and status are required.");
  const db = getFirestore();
  const ref = db.collection("deliveryRequests").doc(id);
  const snap = await ref.get();
  const before = snap.exists ? snap.data() : {};
  const patch = operationStatusPatch(status, actor, reason);
  await ref.set(patch, {merge: true});
  await writeAudit(db, actor, {
    actionType: `delivery_operation_${status}`,
    recordType: "deliveryRequests",
    recordId: id,
    reason,
  }, before, patch);
  return {ok: true};
});

exports.adminArchiveDelivery = functions.https.onCall(async (data, context) => {
  const actor = await resolveActor(context);
  requireOperations(actor);
  const id = clean(data.deliveryId);
  if (!id) throw new functions.https.HttpsError("invalid-argument", "Delivery is required.");
  const db = getFirestore();
  const ref = db.collection("deliveryRequests").doc(id);
  const snap = await ref.get();
  const before = snap.exists ? snap.data() : {};
  const patch = {
    adminArchiveStatus: "archived",
    archivedByAdminId: actor.uid,
    archivedByAdminEmail: actor.email || null,
    archivedAt: FieldValue.serverTimestamp(),
    adminArchiveReason: clean(data.reason || "Archived from isolated Circum Admin"),
    updatedAt: FieldValue.serverTimestamp(),
  };
  await ref.set(patch, {merge: true});
  await writeAudit(db, actor, {
    actionType: "delivery_archived",
    recordType: "deliveryRequests",
    recordId: id,
    reason: patch.adminArchiveReason,
  }, before, {adminArchiveStatus: "archived"});
  return {ok: true};
});

exports.adminUpdateIrisReview = functions.https.onCall(async (data, context) => {
  const actor = await resolveActor(context);
  requireOperations(actor);
  const id = clean(data.deliveryId);
  const status = lower(data.status);
  const reason = clean(data.reason || "Updated from Circum Admin Parcel Intelligence");
  if (!id || !status) throw new functions.https.HttpsError("invalid-argument", "Delivery and status are required.");
  const db = getFirestore();
  const ref = db.collection("deliveryRequests").doc(id);
  const snap = await ref.get();
  const before = snap.exists ? snap.data() : {};
  const patch = irisReviewPatch(status, actor, reason);
  await ref.set(patch, {merge: true});
  await writeAudit(db, actor, {
    actionType: `iris_review_${status}`,
    recordType: "deliveryRequests",
    recordId: id,
    reason,
  }, before, patch);
  return {ok: true};
});

exports.adminUpdateSenderAccountStatus = functions.https.onCall(async (data, context) => {
  const actor = await resolveActor(context);
  requireSupport(actor);
  const id = clean(data.userId);
  const status = lower(data.status);
  const reason = clean(data.reason || "Sender account status updated from Admin");
  if (!id || !status) throw new functions.https.HttpsError("invalid-argument", "User and status are required.");
  const db = getFirestore();
  const ref = db.collection("users").doc(id);
  const snap = await ref.get();
  const before = snap.exists ? snap.data() : {};
  const patch = senderAccountPatch(status, actor, reason);
  await ref.set(patch, {merge: true});
  await writeAudit(db, actor, {
    actionType: `sender_account_${status}`,
    recordType: "users",
    recordId: id,
    reason,
  }, before, patch);
  return {ok: true};
});

exports.adminUpdateBusinessAccountStatus = functions.https.onCall(async (data, context) => {
  const actor = await resolveActor(context);
  requireOperations(actor, "Business Operations Admin access is required.");
  const id = clean(data.businessId);
  const status = lower(data.status);
  if (!id || !status) throw new functions.https.HttpsError("invalid-argument", "Business and status are required.");
  const db = getFirestore();
  const ref = db.collection("businessAccounts").doc(id);
  const snap = await ref.get();
  const before = snap.exists ? snap.data() : {};
  const patch = businessStatusPatch(status, actor);
  await ref.set(patch, {merge: true});
  await writeAudit(db, actor, {
    actionType: `business_account_${status}`,
    recordType: "businessAccounts",
    recordId: id,
    reason: clean(data.reason || "Business account status updated from Admin"),
  }, before, patch);
  return {ok: true};
});

exports.adminUpdateBusinessOperation = functions.https.onCall(async (data, context) => {
  const actor = await resolveActor(context);
  requireOperations(actor, "Business Operations Admin access is required.");
  const id = clean(data.businessId);
  const status = lower(data.status);
  const reason = clean(data.reason || "Updated from Circum Admin Business Operations");
  if (!id || !status) throw new functions.https.HttpsError("invalid-argument", "Business and status are required.");
  const db = getFirestore();
  const ref = db.collection("businessAccounts").doc(id);
  const snap = await ref.get();
  const before = snap.exists ? snap.data() : {};
  const patch = businessOperationPatch(status, actor, reason);
  await ref.set(patch, {merge: true});
  await writeAudit(db, actor, {
    actionType: `business_operation_${status}`,
    recordType: "businessAccounts",
    recordId: id,
    reason,
  }, before, patch);
  return {ok: true};
});

exports.adminUpdateBusinessMember = functions.https.onCall(async (data, context) => {
  const actor = await resolveActor(context);
  requireOperations(actor, "Business Operations Admin access is required.");
  const businessId = clean(data.businessId);
  const index = Number(data.memberIndex);
  if (!businessId || !Number.isInteger(index) || index < 0) {
    throw new functions.https.HttpsError("invalid-argument", "Business member is required.");
  }
  const db = getFirestore();
  const ref = db.collection("businessAccounts").doc(businessId);
  let beforeMember = {};
  let afterMember = {};
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new functions.https.HttpsError("not-found", "Business account was not found.");
    const account = snap.data() || {};
    const members = Array.isArray(account.teamMembers) ? account.teamMembers.map((member) => ({...member})) : [];
    if (index >= members.length) throw new functions.https.HttpsError("not-found", "Business member was not found.");
    beforeMember = {...members[index]};
    if (data.remove === true) {
      afterMember = {memberRemoved: true, member: beforeMember.email || beforeMember.userId || null};
      members.splice(index, 1);
    } else {
      members[index] = {
        ...members[index],
        role: clean(data.role || members[index].role || "member"),
        updatedAt: Timestamp.now(),
        updatedByAdmin: actor.label,
      };
      afterMember = {...members[index]};
    }
    tx.set(ref, {
      teamMembers: members,
      updatedAt: FieldValue.serverTimestamp(),
      updatedBy: actor.uid,
      updatedByEmail: actor.email || null,
    }, {merge: true});
  });
  await writeAudit(db, actor, {
    actionType: data.remove === true ? "business_member_removed" : "business_member_role_updated",
    recordType: "businessAccounts",
    recordId: businessId,
    reason: clean(data.reason || "Business member updated from Admin"),
  }, beforeMember, afterMember);
  return {ok: true};
});

exports.adminUpdateHealthPlusPickup = functions.https.onCall(async (data, context) => {
  const actor = await resolveActor(context);
  requireOperations(actor, "Health+ Operations Admin access is required.");
  const id = clean(data.pickupId);
  const status = lower(data.status);
  const reason = clean(data.reason || "Updated from Circum Admin Health+ Operations");
  if (!id || !status) throw new functions.https.HttpsError("invalid-argument", "Health+ pickup and status are required.");
  const db = getFirestore();
  const ref = db.collection("prescriptionPickups").doc(id);
  const snap = await ref.get();
  const before = snap.exists ? snap.data() : {};
  const patch = healthStatusPatch(status, actor, reason);
  await ref.set(patch, {merge: true});
  await db.collection("healthPlusUsageEvents").add({
    type: "admin_status_updated",
    pickupId: id,
    status,
    source: "circum-admin",
    adminUserId: actor.uid,
    createdAt: FieldValue.serverTimestamp(),
  });
  await writeAudit(db, actor, {
    actionType: "health_plus_status_update",
    recordType: "prescriptionPickups",
    recordId: id,
    reason,
  }, before, patch);
  return {ok: true};
});

exports.adminUpdateHealthPlusSchedule = functions.https.onCall(async (data, context) => {
  const actor = await resolveActor(context);
  requireOperations(actor, "Health+ Operations Admin access is required.");
  const id = clean(data.scheduleId);
  const status = lower(data.status);
  if (!id || !status) throw new functions.https.HttpsError("invalid-argument", "Health+ schedule and status are required.");
  const db = getFirestore();
  const ref = db.collection("recurringPickupSchedules").doc(id);
  const snap = await ref.get();
  const before = snap.exists ? snap.data() : {};
  const patch = {
    status,
    adminReviewStatus: status,
    updatedAt: FieldValue.serverTimestamp(),
    adminUpdatedBy: actor.label,
    adminReason: clean(data.reason || "Health+ recurring schedule reviewed from Admin"),
  };
  await ref.set(patch, {merge: true});
  await db.collection("healthPlusCustodyArchive").add({
    scheduleId: id,
    profileId: before.profileId || null,
    userId: before.userId || before.senderId || null,
    eventType: `schedule_${status}`,
    timestamp: FieldValue.serverTimestamp(),
    actorType: "admin",
    actorId: actor.uid,
    actorName: actor.email || actor.uid,
    publicMessage: "Your Health+ recurring schedule has been reviewed.",
    internalNote: `Schedule ${status} from isolated Circum Admin.`,
    statusAfterEvent: status,
    createdAt: FieldValue.serverTimestamp(),
  });
  await writeAudit(db, actor, {
    actionType: `health_plus_schedule_${status}`,
    recordType: "recurringPickupSchedules",
    recordId: id,
    reason: patch.adminReason,
  }, before, patch);
  return {ok: true};
});

exports.adminUpdateHealthPlusProfile = functions.https.onCall(async (data, context) => {
  const actor = await resolveActor(context);
  requireOperations(actor, "Health+ Operations Admin access is required.");
  const id = clean(data.profileId);
  const status = lower(data.status);
  if (!id || !status) throw new functions.https.HttpsError("invalid-argument", "Health+ profile and status are required.");
  const db = getFirestore();
  const ref = db.collection("healthPlusProfiles").doc(id);
  const snap = await ref.get();
  const before = snap.exists ? snap.data() : {};
  const patch = {
    status,
    adminReviewStatus: status,
    updatedAt: FieldValue.serverTimestamp(),
    adminUpdatedBy: actor.label,
    adminReason: clean(data.reason || "Health+ profile reviewed from Admin"),
  };
  await ref.set(patch, {merge: true});
  await db.collection("healthPlusCustodyArchive").add({
    profileId: id,
    userId: before.userId || before.senderId || null,
    eventType: `profile_${status}`,
    timestamp: FieldValue.serverTimestamp(),
    actorType: "admin",
    actorId: actor.uid,
    actorName: actor.email || actor.uid,
    internalNote: `Profile ${status} from isolated Circum Admin.`,
    statusAfterEvent: status,
    createdAt: FieldValue.serverTimestamp(),
  });
  await writeAudit(db, actor, {
    actionType: `health_plus_profile_${status}`,
    recordType: "healthPlusProfiles",
    recordId: id,
    reason: patch.adminReason,
  }, before, patch);
  return {ok: true};
});

exports.adminUpdateFinanceWorkflow = functions.https.onCall(async (data, context) => {
  const actor = await resolveActor(context);
  requireFinance(actor);
  const id = clean(data.paymentId);
  const status = lower(data.status);
  if (!id || !status) throw new functions.https.HttpsError("invalid-argument", "Finance record and status are required.");
  const db = getFirestore();
  const ref = db.collection("payments").doc(id);
  const snap = await ref.get();
  const before = snap.exists ? snap.data() : {};
  const patch = financePatch(status, actor);
  await ref.set(patch, {merge: true});
  await writeAudit(db, actor, {
    actionType: `finance_workflow_${status}`,
    recordType: "payments",
    recordId: id,
    reason: clean(data.reason || "Finance workflow updated from Admin"),
  }, before, patch);
  return {ok: true};
});

exports.adminRequestAccountMergeReview = functions.https.onCall(async (data, context) => {
  const actor = await resolveActor(context);
  requireSupport(actor);
  const primaryAccountId = clean(data.primaryAccountId);
  const duplicateAccountId = clean(data.duplicateAccountId);
  const accountType = clean(data.accountType || "users");
  if (!primaryAccountId || !duplicateAccountId || primaryAccountId === duplicateAccountId) {
    throw new functions.https.HttpsError("invalid-argument", "Two distinct accounts are required.");
  }
  const db = getFirestore();
  const record = {
    primaryAccountId,
    duplicateAccountId,
    accountType,
    status: "pending_review",
    requestedBy: actor.label,
    createdAt: FieldValue.serverTimestamp(),
  };
  const ref = await db.collection("accountMergeReviews").add(record);
  await writeAudit(db, actor, {
    actionType: "account_merge_review_requested",
    recordType: "accountMergeReviews",
    recordId: ref.id,
    reason: clean(data.reason || "Duplicate account merge review requested from Admin"),
  }, {}, record);
  return {ok: true, reviewId: ref.id};
});

exports.adminUpdateGiftWorkflow = functions.https.onCall(async (data, context) => {
  const actor = await resolveActor(context);
  requireSupport(actor, "Gift Operations Admin access is required.");
  const id = clean(data.giftId);
  const collection = clean(data.collection || "giftOrders");
  const status = lower(data.status);
  const reason = clean(data.reason || "Gift workflow action confirmed from Admin");
  if (!id || !["giftOrders", "giftRequests"].includes(collection)) {
    throw new functions.https.HttpsError("invalid-argument", "Gift record is required.");
  }
  const db = getFirestore();
  const ref = db.collection(collection).doc(id);
  const snap = await ref.get();
  const before = snap.exists ? snap.data() : {};
  const patch = giftWorkflowPatch(status, actor, reason);
  await ref.set(patch, {merge: true});
  await writeAudit(db, actor, {
    actionType: `gift_workflow_${status}`,
    recordType: collection,
    recordId: id,
    reason,
  }, before, patch);
  return {ok: true};
});

exports.adminUpdateGiftCampaignParticipant = functions.https.onCall(async (data, context) => {
  const actor = await resolveActor(context);
  requireSupport(actor, "Gift Campaign Admin access is required.");
  const id = clean(data.participantId);
  const status = lower(data.status);
  if (!id || !status) {
    throw new functions.https.HttpsError("invalid-argument", "Campaign participant and status are required.");
  }
  const db = getFirestore();
  const ref = db.collection("giftCampaignParticipants").doc(id);
  const snap = await ref.get();
  const before = snap.exists ? snap.data() : {};
  const patch = giftCampaignParticipantPatch(status, actor);
  await ref.set(patch, {merge: true});
  await writeAudit(db, actor, {
    actionType: `gift_campaign_participant_${status}`,
    recordType: "giftCampaignParticipants",
    recordId: id,
    reason: clean(data.reason || "Gift campaign participant reviewed from Admin"),
  }, before, patch);
  return {ok: true};
});

exports.adminSaveGiftBrandPartner = functions.https.onCall(async (data, context) => {
  const actor = await resolveActor(context);
  requireSupport(actor, "Brand Partner Admin access is required.");
  const name = clean(data.partnerName || data.brandName);
  const id = clean(data.brandId || data.partnerId || name.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, ""));
  if (!id || !name) {
    throw new functions.https.HttpsError("invalid-argument", "Brand Partner name is required.");
  }
  const db = getFirestore();
  const ref = db.collection("giftBrands").doc(id);
  const snap = await ref.get();
  const before = snap.exists ? snap.data() : {};
  const patch = {
    partnerId: id,
    ...(!snap.exists ? {createdAt: FieldValue.serverTimestamp(), createdBy: actor.label} : {}),
    ...giftBrandPatch(data, actor),
  };
  await ref.set(patch, {merge: true});
  await writeAudit(db, actor, {
    actionType: snap.exists ? "gift_brand_partner_saved" : "gift_brand_partner_created",
    recordType: "giftBrands",
    recordId: id,
    reason: clean(data.reason || "Brand Partner profile saved from Admin"),
  }, before, patch);
  return {ok: true, brandId: id};
});

exports.adminSuggestGiftCampaignMatch = functions.https.onCall(async (data, context) => {
  const actor = await resolveActor(context);
  requireSupport(actor, "Gift Campaign Admin access is required.");
  const participantId = clean(data.participantId);
  const suggestedParticipantId = clean(data.suggestedParticipantId);
  const suggestedMatchReason = clean(data.suggestedMatchReason);
  const suggestedMatchScore = Number(data.suggestedMatchScore || 0);
  if (!participantId || !suggestedParticipantId || suggestedMatchScore <= 0 || !suggestedMatchReason) {
    throw new functions.https.HttpsError("invalid-argument", "A valid campaign match suggestion is required.");
  }
  const db = getFirestore();
  const ref = db.collection("giftCampaignParticipants").doc(participantId);
  const snap = await ref.get();
  const before = snap.exists ? snap.data() : {};
  const patch = {
    suggestedParticipantId,
    suggestedMatchScore,
    suggestedMatchReason,
    updatedAt: FieldValue.serverTimestamp(),
    updatedBy: actor.label,
  };
  await ref.set(patch, {merge: true});
  await writeAudit(db, actor, {
    actionType: "gift_campaign_match_suggested",
    recordType: "giftCampaignParticipants",
    recordId: participantId,
    reason: suggestedMatchReason,
  }, before, patch);
  return {ok: true};
});

exports.adminApproveGiftCampaignMatch = functions.https.onCall(async (data, context) => {
  const actor = await resolveActor(context);
  requireSupport(actor, "Gift Campaign Admin access is required.");
  const participantId = clean(data.participantId);
  if (!participantId) {
    throw new functions.https.HttpsError("invalid-argument", "Campaign participant is required.");
  }
  const db = getFirestore();
  const participantRef = db.collection("giftCampaignParticipants").doc(participantId);
  const matchRef = db.collection("giftCampaignMatches").doc();
  let otherId = "";
  let score = 0;
  let reason = "";
  await db.runTransaction(async (tx) => {
    const participantSnap = await tx.get(participantRef);
    if (!participantSnap.exists) {
      throw new functions.https.HttpsError("not-found", "Campaign participant was not found.");
    }
    const participant = participantSnap.data() || {};
    otherId = clean(participant.suggestedParticipantId);
    if (!otherId) {
      throw new functions.https.HttpsError("failed-precondition", "Generate a campaign match suggestion first.");
    }
    const otherRef = db.collection("giftCampaignParticipants").doc(otherId);
    const otherSnap = await tx.get(otherRef);
    if (!otherSnap.exists) {
      throw new functions.https.HttpsError("not-found", "Suggested participant was not found.");
    }
    const other = otherSnap.data() || {};
    reason = clean(participant.suggestedMatchReason);
    score = Number(participant.suggestedMatchScore || 0);
    for (const [currentRef, current, partner] of [
      [participantRef, participant, other],
      [otherRef, other, participant],
    ]) {
      tx.set(currentRef, {
        matchStatus: "matched",
        adminReviewStatus: "approved",
        matchedParticipantId: currentRef.id === participantId ? otherId : participantId,
        matchId: matchRef.id,
        matchScore: score,
        matchReason: reason,
        matchLockedAt: FieldValue.serverTimestamp(),
        matchApprovedBy: actor.uid,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      const giftRef = db.collection("giftRequests").doc();
      tx.set(giftRef, giftRequestForCampaign(current, partner, participant, matchRef.id));
    }
    tx.set(matchRef, {
      campaignId: participant.campaignId || null,
      campaignName: participant.campaignName || null,
      participantIds: [participantId, otherId],
      matchScore: score,
      matchReason: reason,
      status: "approved",
      approvedBy: actor.uid,
      approvedByEmail: actor.email || null,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  await writeAudit(db, actor, {
    actionType: "gift_campaign_match_approved",
    recordType: "giftCampaignMatches",
    recordId: matchRef.id,
    reason: clean(data.reason || "Campaign Matching approval confirmed from Admin"),
  }, {}, {participantIds: [participantId, otherId], score});
  return {ok: true, matchId: matchRef.id};
});

exports.adminBulkGiftCampaignAction = functions.https.onCall(async (data, context) => {
  const actor = await resolveActor(context);
  requireSupport(actor, "Gift Campaign Admin access is required.");
  const action = lower(data.action);
  const participantIds = Array.isArray(data.participantIds) ?
    data.participantIds.map(clean).filter(Boolean).slice(0, 25) : [];
  if (!participantIds.length || !action) {
    throw new functions.https.HttpsError("invalid-argument", "Campaign participants and action are required.");
  }
  const db = getFirestore();
  const batch = db.batch();
  for (const id of participantIds) {
    batch.set(
        db.collection("giftCampaignParticipants").doc(id),
        giftCampaignParticipantPatch(action, actor),
        {merge: true},
    );
  }
  await batch.commit();
  await writeAudit(db, actor, {
    actionType: `gift_campaign_match_bulk_${action}`,
    recordType: "giftCampaignParticipants",
    recordId: "bulk",
    reason: clean(data.reason || "Bulk Campaign Matching workflow confirmed from Admin"),
  }, {}, {count: participantIds.length, action});
  return {ok: true, count: participantIds.length};
});

exports.adminUpdateIrisRepositoryRecord = functions.https.onCall(async (data, context) => {
  const actor = await resolveActor(context);
  requireOperations(actor, "IRIS Operations Admin access is required.");
  const id = clean(data.recordId);
  const collection = clean(data.collection || "irisCanonicalObjects");
  const action = lower(data.action);
  if (!id || !action || !IRIS_REPOSITORY_COLLECTIONS.has(collection)) {
    throw new functions.https.HttpsError("invalid-argument", "IRIS repository record is required.");
  }
  const db = getFirestore();
  const sourceRef = db.collection(collection).doc(id);
  const sourceSnap = await sourceRef.get();
  const before = sourceSnap.exists ? sourceSnap.data() : {};
  const requestedPatch = allowedAdminPatch(data.patch, IRIS_REPOSITORY_PATCH_FIELDS);
  const targetId = action === "duplicate_review" ?
    slugId(`${requestedPatch.canonicalName || requestedPatch.objectName || before.canonicalName || before.objectName || id}-copy`) :
    id;
  if (!targetId) {
    throw new functions.https.HttpsError("invalid-argument", "IRIS repository target is required.");
  }
  const patch = {
    ...requestedPatch,
    adminRepositoryAction: action,
    repositoryReviewStatus: action,
    ...(action === "duplicate_review" ? {duplicatedFrom: id, createdAt: FieldValue.serverTimestamp()} : {}),
    ...(action === "deactivated" ? {status: "deactivated"} : {}),
    ...(action === "activated" ? {status: "active"} : {}),
    ...(action === "bulk_exported" ? {lastExportedAt: FieldValue.serverTimestamp()} : {}),
    updatedAt: FieldValue.serverTimestamp(),
    updatedBy: actor.label,
  };
  await db.collection(collection).doc(targetId).set(patch, {merge: true});
  await writeAudit(db, actor, {
    actionType: `iris_repository_${action}`,
    recordType: collection,
    recordId: targetId,
    reason: clean(data.reason || "IRIS repository governance action confirmed from Admin"),
  }, before, patch);
  return {ok: true, recordId: targetId};
});

exports.adminUpdateIrisCandidateWorkflow = functions.https.onCall(async (data, context) => {
  const actor = await resolveActor(context);
  requireOperations(actor, "IRIS Operations Admin access is required.");
  const id = clean(data.candidateId);
  const collection = clean(data.collection || "irisLearningCases");
  const action = lower(data.action);
  if (!id || !action || !IRIS_CANDIDATE_COLLECTIONS.has(collection)) {
    throw new functions.https.HttpsError("invalid-argument", "IRIS candidate record is required.");
  }
  const db = getFirestore();
  const candidateRef = db.collection(collection).doc(id);
  const snap = await candidateRef.get();
  if (!snap.exists) {
    throw new functions.https.HttpsError("not-found", "IRIS candidate was not found.");
  }
  const record = snap.data() || {};
  if (action === "promoted") {
    const canonicalId = slugId(record.canonicalName || record.objectName || record.enteredText || record.category || id);
    if (!canonicalId) {
      throw new functions.https.HttpsError("invalid-argument", "IRIS canonical record is required.");
    }
    const batch = db.batch();
    batch.set(db.collection("irisCanonicalObjects").doc(canonicalId), {
      canonicalId,
      objectName: record.objectName || record.enteredText || record.category || id,
      canonicalName: record.canonicalName || record.enteredText || record.objectName || id,
      category: record.category || record.irisCategory || null,
      subcategory: record.subcategory || null,
      knownWeight: record.knownWeight || record.estimatedWeight || record.irisEstimatedWeight || null,
      weightBand: record.weightBand || null,
      vehicleRecommendation: record.vehicleRecommendation || record.recommendedVehicle || null,
      handlingRequirements: record.handlingRequirements || record.handlingNotes || null,
      sourceCandidateId: id,
      status: "active",
      repositoryReviewStatus: "promoted",
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      updatedBy: actor.label,
    }, {merge: true});
    const candidatePatch = {
      learningStatus: "promoted",
      reviewStatus: "promoted",
      repositoryPromotionStatus: "committed",
      promotedCanonicalId: canonicalId,
      reviewedAt: FieldValue.serverTimestamp(),
      reviewedBy: actor.label,
      updatedAt: FieldValue.serverTimestamp(),
    };
    batch.set(candidateRef, candidatePatch, {merge: true});
    await batch.commit();
    await writeAudit(db, actor, {
      actionType: "iris_candidate_promoted",
      recordType: collection,
      recordId: id,
      reason: clean(data.reason || "Candidate promoted to Canonical Repository from Admin"),
    }, record, {promotedCanonicalId: canonicalId});
    return {ok: true, canonicalId};
  }
  const patch = {
    learningStatus: action,
    reviewStatus: action,
    reviewedAt: FieldValue.serverTimestamp(),
    reviewedBy: actor.label,
    updatedAt: FieldValue.serverTimestamp(),
    ...(action === "merge_existing" ? {repositoryMergeStatus: "pending"} : {}),
    ...(action === "save_alias" ? {aliasReviewStatus: "pending"} : {}),
    ...(action === "suspicious" ? {riskReviewStatus: "suspicious"} : {}),
    ...(action === "rejected" ? {rejectedAt: FieldValue.serverTimestamp()} : {}),
    ...(action === "approved" ? {approvedAt: FieldValue.serverTimestamp()} : {}),
  };
  await candidateRef.set(patch, {merge: true});
  await writeAudit(db, actor, {
    actionType: `iris_candidate_${action}`,
    recordType: collection,
    recordId: id,
    reason: clean(data.reason || "IRIS candidate workflow confirmed from Admin"),
  }, record, patch);
  return {ok: true};
});

exports.adminSaveGiftRequestEditor = functions.https.onCall(async (data, context) => {
  const actor = await resolveActor(context);
  requireSupport(actor, "Gift Operations Admin access is required.");
  const id = clean(data.giftId);
  const collection = clean(data.collection || "giftRequests");
  if (!id || !GIFT_EDITOR_COLLECTIONS.has(collection)) {
    throw new functions.https.HttpsError("invalid-argument", "Gift request record is required.");
  }
  const db = getFirestore();
  const ref = db.collection(collection).doc(id);
  const snap = await ref.get();
  const before = snap.exists ? snap.data() : {};
  const patch = giftRequestEditorPatch(data.patch || {}, actor);
  await ref.set(patch, {merge: true});
  await writeAudit(db, actor, {
    actionType: "gift_request_editor_saved",
    recordType: collection,
    recordId: id,
    reason: clean(data.reason || "Historical Gift Request editor workflow restored"),
  }, before, patch);
  return {ok: true};
});

exports.adminUpdateGiftWorkspace = functions.https.onCall(async (data, context) => {
  const actor = await resolveActor(context);
  requireSupport(actor, "Gift Workspace Admin access is required.");
  const id = clean(data.giftId);
  const collection = clean(data.collection || "giftRequests");
  const action = lower(data.action);
  if (!id || !action || !["giftRequests", "giftOrders"].includes(collection)) {
    throw new functions.https.HttpsError("invalid-argument", "Gift workspace record is required.");
  }
  const db = getFirestore();
  const ref = db.collection(collection).doc(id);
  const snap = await ref.get();
  const before = snap.exists ? snap.data() : {};
  const patch = {
    "giftsTeamWorkspace.status": action,
    "giftsTeamWorkspace.updatedAt": FieldValue.serverTimestamp(),
    "giftsTeamWorkspace.updatedBy": actor.label,
    "giftWorkspaceAuditTrail": FieldValue.arrayUnion([{
      event: action,
      updatedBy: actor.label,
      updatedAt: new Date().toISOString(),
    }]),
    ...(action === "ready_for_procurement" ? {"giftsTeamWorkspace.readiness.readyForProcurement": true} : {}),
    ...(action === "ready_for_rider" ? {"giftsTeamWorkspace.readiness.readyForRider": true} : {}),
    ...(action === "ready_for_scheduling" ? {"giftsTeamWorkspace.readiness.readyForScheduling": true} : {}),
    ...(action === "ready_for_delivery" ? {"giftsTeamWorkspace.readiness.readyForDelivery": true} : {}),
  };
  await ref.set(patch, {merge: true});
  await writeAudit(db, actor, {
    actionType: `gift_workspace_${action}`,
    recordType: collection,
    recordId: id,
    reason: clean(data.reason || "Gift Team workspace action confirmed from Admin"),
  }, before, {workspaceStatus: action});
  return {ok: true};
});

exports.adminUpdatePlatformRecord = functions.https.onCall(async (data, context) => {
  const actor = await resolveActor(context);
  requireManageAdmins(actor);
  const id = clean(data.recordId);
  const collection = clean(data.collection);
  const status = lower(data.status);
  if (!id || !PLATFORM_OPERATION_COLLECTIONS.has(collection)) {
    throw new functions.https.HttpsError("invalid-argument", "Platform record is required.");
  }
  const db = getFirestore();
  const ref = db.collection(collection).doc(id);
  const snap = await ref.get();
  const before = snap.exists ? snap.data() : {};
  const patch = platformOperationPatch(status, actor, data.reason || "Platform operation confirmed from Admin");
  await ref.set(patch, {merge: true});
  await writeAudit(db, actor, {
    actionType: `platform_operation_${status}`,
    recordType: collection,
    recordId: id,
    reason: clean(data.reason || "Platform operation updated from Admin"),
  }, before, patch);
  return {ok: true};
});

exports.adminAddAdminNote = functions.https.onCall(async (data, context) => {
  const actor = await resolveActor(context);
  requireSupport(actor);
  const recordType = clean(data.recordType);
  const recordId = clean(data.recordId);
  const body = clean(data.body || data.note);
  if (!recordType || !recordId || !body) {
    throw new functions.https.HttpsError("invalid-argument", "A note target and body are required.");
  }
  const db = getFirestore();
  const note = {
    recordType,
    recordId,
    body,
    note: body,
    pinned: data.pinned === true,
    operatorId: actor.uid,
    operatorEmail: actor.email || null,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
  const ref = await db.collection("adminNotes").add(note);
  await writeAudit(db, actor, {
    actionType: "admin_note_added",
    recordType,
    recordId,
    reason: clean(data.reason || "Internal Admin note added"),
  }, {}, {noteId: ref.id, pinned: note.pinned});
  return {ok: true, noteId: ref.id};
});

exports.adminRecordRiderEvent = functions.https.onCall(async (data, context) => {
  const actor = await resolveActor(context);
  requireAnyRole(actor, ["admin", "super_admin", "operations_admin", "driver_manager"], "Rider Operations Admin access is required.");
  const riderId = clean(data.riderId);
  const action = lower(data.action);
  if (!riderId || !action) {
    throw new functions.https.HttpsError("invalid-argument", "Rider and action are required.");
  }
  const db = getFirestore();
  const event = {
    riderId,
    adminId: actor.uid,
    adminEmail: actor.email || null,
    action,
    previousStatus: clean(data.previousStatus),
    newStatus: clean(data.newStatus),
    note: clean(data.note),
    createdAt: FieldValue.serverTimestamp(),
  };
  const ref = await db.collection("riderAdminEvents").add(event);
  await writeAudit(db, actor, {
    actionType: `rider_event_${action}`,
    recordType: "riderAdminEvents",
    recordId: ref.id,
    reason: clean(data.reason || data.note || "Rider Admin event recorded"),
  }, {}, event);
  return {ok: true, eventId: ref.id};
});

exports.adminResolveMessageReport = functions.https.onCall(async (data, context) => {
  const actor = await resolveActor(context);
  requireSupport(actor);
  const id = clean(data.reportId);
  const status = lower(data.status);
  if (!id || !status) {
    throw new functions.https.HttpsError("invalid-argument", "Message report and status are required.");
  }
  const db = getFirestore();
  const ref = db.collection("messageReports").doc(id);
  const snap = await ref.get();
  const before = snap.exists ? snap.data() : {};
  const patch = {
    status,
    reviewStatus: status,
    resolvedAt: FieldValue.serverTimestamp(),
    resolvedBy: actor.label,
    adminResolution: status,
    updatedAt: FieldValue.serverTimestamp(),
  };
  await ref.set(patch, {merge: true});
  await writeAudit(db, actor, {
    actionType: `message_report_${status}`,
    recordType: "messageReports",
    recordId: id,
    reason: clean(data.reason || "Message report reviewed from Admin"),
  }, before, patch);
  return {ok: true};
});
