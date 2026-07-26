/* eslint-disable max-len, require-jsdoc */
const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue, Timestamp} = require("firebase-admin/firestore");

const ADMIN_ROLES = new Set(["admin", "super_admin", "operations_admin"]);
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
