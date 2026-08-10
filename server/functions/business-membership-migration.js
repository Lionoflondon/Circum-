/* eslint-disable max-len, require-jsdoc */
"use strict";

const crypto = require("node:crypto");
const functions = require("firebase-functions/v1");
const {getFirestore, FieldPath, FieldValue} = require("firebase-admin/firestore");

function clean(value) {
  return `${value || ""}`.trim();
}

function emailKey(email) {
  return crypto.createHash("sha256").update(clean(email).toLowerCase()).digest("hex").slice(0, 32);
}

function membershipId(businessId, member = {}) {
  const uid = clean(member.userId);
  if (uid && !uid.includes("@")) return `${businessId}_${uid}`;
  return `${businessId}_invite_${emailKey(member.email || uid)}`;
}

function legacyMembers(account = {}) {
  const existing = Array.isArray(account.teamMembers) ? account.teamMembers : [];
  const ownerUid = clean(account.ownerUid || account.createdByUserId);
  const ownerEmail = clean(account.contactEmail || account.billingEmail).toLowerCase();
  const members = existing.map((member) => ({...member}));
  if (ownerUid && !members.some((member) => clean(member.userId) === ownerUid)) {
    members.push({userId: ownerUid, email: ownerEmail, name: account.contactName || "", role: "owner", status: "active"});
  }
  return members.filter((member) => clean(member.userId || member.email));
}

async function migrateAccount(db, accountDoc) {
  const account = accountDoc.data() || {};
  if (account.membershipAuthorityVersion === "business_memberships_v2") return 0;
  const members = legacyMembers(account);
  const batch = db.batch();
  members.forEach((member) => {
    const id = membershipId(accountDoc.id, member);
    batch.set(db.collection("businessMemberships").doc(id), {
      businessId: accountDoc.id,
      userId: clean(member.userId) && !clean(member.userId).includes("@") ? clean(member.userId) : null,
      email: clean(member.email || member.userId).toLowerCase(),
      name: clean(member.name),
      role: clean(member.role || "member").toLowerCase(),
      customRoleId: clean(member.customRoleId) || null,
      status: clean(member.status || "active").toLowerCase(),
      migratedFromLegacyAccount: true,
      createdAt: member.createdAt || member.joinedAt || FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  });
  batch.set(accountDoc.ref, {
    membershipAuthorityVersion: "business_memberships_v2",
    membershipMigratedAt: FieldValue.serverTimestamp(),
    teamMembers: FieldValue.delete(),
    teamMemberIds: FieldValue.delete(),
    managerIds: FieldValue.delete(),
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  await batch.commit();
  return members.length;
}

exports.migrateBusinessMembershipAuthority = functions.pubsub.schedule("every 10 minutes").onRun(async () => {
  const db = getFirestore();
  const stateRef = db.collection("systemMigrationState").doc("business_memberships_v2");
  const state = await stateRef.get();
  if (state.exists && state.data().status === "completed") return null;
  let query = db.collection("businessAccounts").orderBy(FieldPath.documentId()).limit(20);
  const cursor = state.exists ? clean(state.data().cursor) : "";
  if (cursor) query = query.startAfter(cursor);
  const snapshot = await query.get();
  let memberships = 0;
  for (const accountDoc of snapshot.docs) memberships += await migrateAccount(db, accountDoc);
  const last = snapshot.docs.length ? snapshot.docs[snapshot.docs.length - 1].id : cursor;
  await stateRef.set({
    status: snapshot.size < 20 ? "completed" : "running",
    cursor: last,
    accountsProcessed: FieldValue.increment(snapshot.size),
    membershipsProcessed: FieldValue.increment(memberships),
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  return null;
});

exports._private = {emailKey, membershipId, legacyMembers, migrateAccount};
