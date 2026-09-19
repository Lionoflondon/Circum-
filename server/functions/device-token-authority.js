/* eslint-disable max-len, require-jsdoc */
"use strict";

const crypto = require("node:crypto");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");

const TOKEN_COLLECTION = "notificationTokens";
const PROFILE_COLLECTIONS = Object.freeze(["users", "senders", "riderProfiles", "riders"]);
const TOKEN_FIELDS = Object.freeze(["fcmToken", "pushToken", "code"]);

function clean(value, max = 4096) {
  return `${value || ""}`.trim().slice(0, max);
}

function normalizeRole(value) {
  const role = clean(value, 32).toLowerCase();
  if (role === "sender" || role === "shipper") return "sender";
  if (role === "rider" || role === "driver" || role === "courier") return "rider";
  throw new TypeError("Notification token role must be sender or rider.");
}

function canonicalRole(value) {
  try {
    return normalizeRole(value);
  } catch (_) {
    return "";
  }
}

function tokenHash(token) {
  const normalized = clean(token);
  if (!normalized) throw new TypeError("Push token is required.");
  return crypto.createHash("sha256").update(normalized).digest("hex");
}

function roleCollections(role) {
  return normalizeRole(role) === "rider" ? ["riderProfiles", "riders"] : ["users", "senders"];
}

async function registerProfileToken({uid, role, token, db = getFirestore()}) {
  const ownerUid = clean(uid, 128);
  const ownerRole = normalizeRole(role);
  const normalizedToken = clean(token);
  if (!ownerUid || !normalizedToken) throw new TypeError("Push token owner and token are required.");
  const hash = tokenHash(normalizedToken);
  const authorityRef = db.collection(TOKEN_COLLECTION).doc(hash);
  const primaryProfileRef = db.collection(roleCollections(ownerRole)[0]).doc(ownerUid);

  await db.runTransaction(async (transaction) => {
    const querySnapshots = [];
    await transaction.get(authorityRef);
    for (const collection of PROFILE_COLLECTIONS) {
      for (const field of TOKEN_FIELDS) {
        querySnapshots.push(await transaction.get(db.collection(collection).where(field, "==", normalizedToken)));
      }
    }
    const staleRefs = new Map();
    for (const snapshot of querySnapshots) {
      for (const doc of snapshot.docs) staleRefs.set(doc.ref.path, doc.ref);
    }
    for (const ref of staleRefs.values()) {
      transaction.set(ref, {
        fcmToken: FieldValue.delete(), pushToken: FieldValue.delete(), code: FieldValue.delete(),
        notificationTokenUpdatedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    }
    transaction.set(primaryProfileRef, {
      fcmToken: normalizedToken,
      notificationTokenUpdatedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    transaction.set(authorityRef, {
      tokenHash: hash, uid: ownerUid, role: ownerRole, active: true,
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  return {tokenHash: hash, uid: ownerUid, role: ownerRole};
}

async function ownedProfileToken(uid, role, {db = getFirestore()} = {}) {
  const ownerUid = clean(uid, 128);
  if (!ownerUid) return "";
  const ownerRole = normalizeRole(role);
  for (const collection of roleCollections(ownerRole)) {
    const profile = await db.collection(collection).doc(ownerUid).get();
    if (!profile.exists) continue;
    const data = profile.data() || {};
    for (const field of TOKEN_FIELDS) {
      const candidate = clean(data[field]);
      if (!candidate) continue;
      const hash = tokenHash(candidate);
      const authority = await db.collection(TOKEN_COLLECTION).doc(hash).get();
      const record = authority.exists ? authority.data() || {} : {};
      if (record.active === true && clean(record.uid, 128) === ownerUid && canonicalRole(record.role) === ownerRole && clean(record.tokenHash) === hash) return candidate;
    }
  }
  return "";
}

module.exports = {registerProfileToken, ownedProfileToken, tokenHash, normalizeRole, PROFILE_COLLECTIONS, TOKEN_FIELDS, TOKEN_COLLECTION};
