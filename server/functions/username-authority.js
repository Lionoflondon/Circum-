/* eslint-disable max-len, require-jsdoc */
"use strict";

const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");

const RESERVED = new Set([
  "admin", "support", "circum", "iris", "roth", "health", "healthplus",
  "gift", "gifts", "business", "rider", "sender", "system", "official",
]);

function normalizeUsername(value) {
  const raw = String(value || "").trim().replace(/^@+/, "");
  if (!raw || raw.length < 3 || raw.length > 30) {
    throw new functions.https.HttpsError("invalid-argument", "Choose a username between 3 and 30 characters.");
  }
  if (!/^[a-zA-Z0-9_]+$/.test(raw)) {
    throw new functions.https.HttpsError("invalid-argument", "Usernames may use letters, numbers and underscores only.");
  }
  const normalized = raw.toLowerCase();
  if (RESERVED.has(normalized)) {
    throw new functions.https.HttpsError("failed-precondition", "That username is reserved.");
  }
  return {normalized, display: raw};
}

function requireOwner(context) {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Sign in to choose a username.");
  return context.auth.uid;
}

exports.claimCircumUsername = functions.runWith({enforceAppCheck: true}).https.onCall(async (data, context) => {
  const uid = requireOwner(context);
  const {normalized, display} = normalizeUsername(data && data.username);
  const db = getFirestore();
  const registryRef = db.collection("usernames").doc(normalized);
  const userRef = db.collection("users").doc(uid);
  const riderRef = db.collection("riderProfiles").doc(uid);
  const riderLegacyRef = db.collection("riders").doc(uid);

  await db.runTransaction(async (transaction) => {
    const [registrySnap, userSnap, riderProfileSnap, riderSnap] = await Promise.all([
      transaction.get(registryRef),
      transaction.get(userRef),
      transaction.get(riderRef),
      transaction.get(riderLegacyRef),
    ]);
    const current = [userSnap.data(), riderProfileSnap.data(), riderSnap.data()]
        .map((value) => value && (value.username || value.handle || value.riderHandle))
        .find(Boolean);
    if (registrySnap.exists && registrySnap.data().uid !== uid) {
      throw new functions.https.HttpsError("already-exists", "That username is already taken.");
    }
    if (current && String(current).trim().replace(/^@+/, "").toLowerCase() === normalized) {
      if (!registrySnap.exists) {
        transaction.create(registryRef, {
          uid,
          canonicalHandle: normalized,
          displayHandle: display,
          status: "active",
          createdAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
      return;
    }
    const previous = current && String(current).trim().replace(/^@+/, "").toLowerCase();
    const previousRef = previous && previous !== normalized ?
      db.collection("usernames").doc(previous) : null;
    const previousSnap = previousRef ? await transaction.get(previousRef) : null;
    if (previousSnap && previousSnap.exists && previousSnap.data().uid !== uid) {
      throw new functions.https.HttpsError("failed-precondition", "The current username is under review.");
    }
    if (registrySnap.exists) {
      transaction.update(registryRef, {displayHandle: display, updatedAt: FieldValue.serverTimestamp()});
    } else {
      transaction.create(registryRef, {
        uid,
        canonicalHandle: normalized,
        displayHandle: display,
        status: "active",
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    if (previousRef && previous !== normalized && (!previousSnap || !previousSnap.exists)) {
      transaction.create(previousRef, {
        uid,
        canonicalHandle: previous,
        displayHandle: previous,
        status: "tombstoned",
        previousOwner: uid,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    } else if (previousRef && previous !== normalized && previousSnap && previousSnap.exists) {
      transaction.update(previousRef, {
        status: "tombstoned",
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    transaction.set(userRef, {username: normalized, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
    if (riderProfileSnap.exists) transaction.set(riderRef, {username: normalized, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
    if (riderSnap.exists) transaction.set(riderLegacyRef, {username: normalized, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
  });
  return {ok: true, username: normalized, handle: `@${normalized}`};
});

exports._normalizeUsername = normalizeUsername;
