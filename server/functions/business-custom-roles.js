/* eslint-disable max-len, require-jsdoc */
"use strict";

const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {
  canonicalMemberRole,
  normalizedPermissions,
  resolveBusinessAuthority,
  hasBusinessPermission,
} = require("./business-authority");

function text(value, max = 160) {
  return `${value || ""}`.trim().slice(0, max);
}

async function ownerAccess(db, businessId, context) {
  const uid = context.auth && context.auth.uid;
  if (!uid) throw new functions.https.HttpsError("unauthenticated", "Sign in to manage business roles.");
  const accountRef = db.collection("businessAccounts").doc(businessId);
  const accountSnap = await accountRef.get();
  if (!accountSnap.exists) throw new functions.https.HttpsError("not-found", "Business workspace not found.");
  const role = canonicalMemberRole(accountSnap.data() || {}, uid, context.auth.token.email);
  if (role !== "owner") throw new functions.https.HttpsError("permission-denied", "Only the Business Owner can manage custom roles.");
  return {uid, accountRef, account: accountSnap.data() || {}};
}

async function roleAssignmentAccess(db, businessId, context) {
  const uid = context.auth && context.auth.uid;
  if (!uid) throw new functions.https.HttpsError("unauthenticated", "Sign in to manage business roles.");
  const accountRef = db.collection("businessAccounts").doc(businessId);
  const accountSnap = await accountRef.get();
  if (!accountSnap.exists) throw new functions.https.HttpsError("not-found", "Business workspace not found.");
  const account = accountSnap.data() || {};
  const authority = await resolveBusinessAuthority(db, account, businessId, {
    uid,
    email: context.auth.token && context.auth.token.email,
  });
  if (!hasBusinessPermission(authority, "team.roles.assign", ["owner"])) {
    throw new functions.https.HttpsError("permission-denied", "This Business role cannot assign custom roles.");
  }
  return {uid, accountRef, account, authority};
}

function roleRecord(data, businessId, uid) {
  const name = text(data.name, 80);
  const description = text(data.description, 300);
  const permissions = normalizedPermissions(data.permissions);
  if (!name) throw new functions.https.HttpsError("invalid-argument", "Role name is required.");
  if (!permissions.length) throw new functions.https.HttpsError("invalid-argument", "Choose at least one approved permission.");
  return {businessId, name, description, permissions, updatedBy: uid};
}

async function audit(db, values) {
  await db.collection("businessAuditLogs").add({
    ...values,
    createdAt: FieldValue.serverTimestamp(),
  });
}

exports.saveBusinessCustomRole = functions.runWith({enforceAppCheck: true})
    .region("us-central1").https.onCall(async (data, context) => {
      const db = getFirestore();
      const businessId = text(data && data.businessId);
      const {uid} = await ownerAccess(db, businessId, context);
      const suppliedId = text(data && data.roleId, 120);
      const roleRef = suppliedId ? db.collection("businessCustomRoles").doc(suppliedId) : db.collection("businessCustomRoles").doc();
      const existing = await roleRef.get();
      if (existing.exists && text(existing.data().businessId) !== businessId) throw new functions.https.HttpsError("permission-denied", "Role belongs to another business.");
      const record = roleRecord(data || {}, businessId, uid);
      await roleRef.set({
        ...record,
        roleId: roleRef.id,
        createdBy: existing.exists ? existing.data().createdBy : uid,
        createdAt: existing.exists ? existing.data().createdAt : FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: false});
      await audit(db, {businessId, actorUserId: uid, action: existing.exists ? "business_custom_role_updated" : "business_custom_role_created", roleId: roleRef.id, previousPermissions: existing.exists ? normalizedPermissions(existing.data().permissions) : [], newPermissions: record.permissions});
      return {roleId: roleRef.id, ...record};
    });

exports.deleteBusinessCustomRole = functions.runWith({enforceAppCheck: true})
    .region("us-central1").https.onCall(async (data, context) => {
      const db = getFirestore();
      const businessId = text(data && data.businessId);
      const roleId = text(data && data.roleId, 120);
      const {uid} = await ownerAccess(db, businessId, context);
      const roleRef = db.collection("businessCustomRoles").doc(roleId);
      const role = await roleRef.get();
      if (!role.exists || text(role.data().businessId) !== businessId) throw new functions.https.HttpsError("not-found", "Custom role not found.");
      const inUse = await db.collection("businessMemberships")
          .where("businessId", "==", businessId).where("customRoleId", "==", roleId).limit(1).get();
      if (!inUse.empty) throw new functions.https.HttpsError("failed-precondition", "Reassign members before removing this role.");
      await roleRef.delete();
      await audit(db, {businessId, actorUserId: uid, action: "business_custom_role_removed", roleId, previousPermissions: normalizedPermissions(role.data().permissions), newPermissions: []});
      return {status: "removed", roleId};
    });

exports.assignBusinessCustomRole = functions.runWith({enforceAppCheck: true})
    .region("us-central1").https.onCall(async (data, context) => {
      const db = getFirestore();
      const businessId = text(data && data.businessId);
      const roleId = text(data && data.roleId, 120);
      const memberUserId = text(data && data.memberUserId, 180);
      const {uid, accountRef, authority} = await roleAssignmentAccess(db, businessId, context);
      const role = await db.collection("businessCustomRoles").doc(roleId).get();
      if (!role.exists || text(role.data().businessId) !== businessId) throw new functions.https.HttpsError("not-found", "Custom role not found.");
      const membershipRef = db.collection("businessMemberships").doc(`${businessId}_${memberUserId}`);
      const membership = await membershipRef.get();
      if (!membership.exists) throw new functions.https.HttpsError("not-found", "Team member not found.");
      if (["owner", "admin", "manager"].includes(text(membership.data().role).toLowerCase())) throw new functions.https.HttpsError("failed-precondition", "Business administrators cannot be replaced with a custom role.");
      const targetPermissions = normalizedPermissions(role.data().permissions);
      if (authority.role === "custom" && targetPermissions.some((permission) => !authority.permissions.includes(permission))) {
        throw new functions.https.HttpsError("permission-denied", "A custom role cannot grant permissions it does not hold.");
      }
      const previousRole = text(membership.data().role);
      const previousRoleId = text(membership.data().customRoleId);
      await accountRef.set({updatedAt: FieldValue.serverTimestamp(), updatedByUserId: uid}, {merge: true});
      await membershipRef.set({role: "custom", customRoleId: roleId, updatedAt: FieldValue.serverTimestamp(), updatedByUserId: uid}, {merge: true});
      await audit(db, {businessId, actorUserId: uid, targetUserId: memberUserId, action: "business_custom_role_assigned", previousRoleId: previousRoleId || null, newRoleId: roleId, previousState: {role: previousRole, customRoleId: previousRoleId || null}, newState: {role: "custom", customRoleId: roleId}, reason: text(data && data.reason, 300) || null});
      return {status: "assigned", businessId, memberUserId, roleId};
    });

exports.listBusinessCustomRoles = functions.runWith({enforceAppCheck: true})
    .region("us-central1").https.onCall(async (data, context) => {
      const db = getFirestore();
      const businessId = text(data && data.businessId);
      await ownerAccess(db, businessId, context);
      const roles = await db.collection("businessCustomRoles").where("businessId", "==", businessId).orderBy("name").limit(50).get();
      return {roles: roles.docs.map((doc) => ({roleId: doc.id, name: text(doc.data().name, 80), description: text(doc.data().description, 300), permissions: normalizedPermissions(doc.data().permissions)}))};
    });

exports._private = {roleRecord, text};
