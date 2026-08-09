/* eslint-disable max-len, require-jsdoc */
"use strict";

const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {canonicalMemberRole, normalizedPermissions} = require("./business-authority");

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
      const {uid, account} = await ownerAccess(db, businessId, context);
      const roleRef = db.collection("businessCustomRoles").doc(roleId);
      const role = await roleRef.get();
      if (!role.exists || text(role.data().businessId) !== businessId) throw new functions.https.HttpsError("not-found", "Custom role not found.");
      const inUse = (Array.isArray(account.teamMembers) ? account.teamMembers : []).some((member) => text(member.customRoleId) === roleId && text(member.status) !== "removed");
      if (inUse) throw new functions.https.HttpsError("failed-precondition", "Reassign members before removing this role.");
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
      const {uid, accountRef, account} = await ownerAccess(db, businessId, context);
      const role = await db.collection("businessCustomRoles").doc(roleId).get();
      if (!role.exists || text(role.data().businessId) !== businessId) throw new functions.https.HttpsError("not-found", "Custom role not found.");
      const members = Array.isArray(account.teamMembers) ? [...account.teamMembers] : [];
      const index = members.findIndex((member) => text(member.userId) === memberUserId || text(member.email).toLowerCase() === memberUserId.toLowerCase());
      if (index < 0) throw new functions.https.HttpsError("not-found", "Team member not found.");
      if (text(members[index].role).toLowerCase() === "owner") throw new functions.https.HttpsError("failed-precondition", "Owner role cannot be replaced.");
      const previousRoleId = text(members[index].customRoleId);
      members[index] = {...members[index], role: "custom", customRoleId: roleId, updatedAt: new Date(), updatedByUserId: uid};
      await accountRef.set({teamMembers: members, updatedAt: FieldValue.serverTimestamp(), updatedByUserId: uid}, {merge: true});
      await db.collection("businessMemberships").doc(`${businessId}_${memberUserId}`).set({role: "custom", customRoleId: roleId, updatedAt: FieldValue.serverTimestamp(), updatedByUserId: uid}, {merge: true});
      await audit(db, {businessId, actorUserId: uid, targetUserId: memberUserId, action: "business_custom_role_assigned", previousRoleId: previousRoleId || null, newRoleId: roleId});
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
