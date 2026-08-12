/* eslint-disable max-len */
"use strict";

const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");

const RESERVED = new Set([
  "admin", "administrator", "circum", "circumsupport", "help", "official",
  "root", "security", "support", "system",
]);

function normalizeUsername(value) {
  return `${value || ""}`.trim().replace(/^@+/, "").toLowerCase();
}

function validateUsername(value) {
  const username = normalizeUsername(value);
  if (username.length < 3 || username.length > 30) {
    return {valid: false, reason: "Username must be between 3 and 30 characters."};
  }
  if (!/^[a-z0-9][a-z0-9_]*$/.test(username)) {
    return {valid: false, reason: "Use letters, numbers, and underscores only."};
  }
  if (RESERVED.has(username)) {
    return {valid: false, reason: "That username is reserved."};
  }
  return {valid: true, username};
}

async function claimUsername(data, context, dependencies = {}) {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in to choose a username.");
  }
  const decision = validateUsername(data && data.username);
  if (!decision.valid) {
    throw new functions.https.HttpsError("invalid-argument", decision.reason);
  }
  const db = dependencies.db || getFirestore();
  const uid = context.auth.uid;
  const userRef = db.collection("users").doc(uid);
  const riderRef = db.collection("riders").doc(uid);
  const riderProfileRef = db.collection("riderProfiles").doc(uid);
  const targetRef = db.collection("usernames").doc(decision.username);
  await db.runTransaction(async (transaction) => {
    const [userSnapshot, targetSnapshot, riderSnapshot, riderProfileSnapshot] = await Promise.all([
      transaction.get(userRef),
      transaction.get(targetRef),
      transaction.get(riderRef),
      transaction.get(riderProfileRef),
    ]);
    const user = userSnapshot.exists ? userSnapshot.data() || {} : {};
    const previous = normalizeUsername(user.username);
    if (targetSnapshot.exists && targetSnapshot.data().uid !== uid) {
      throw new functions.https.HttpsError("already-exists", "That username is not available.");
    }
    if (previous && previous !== decision.username) {
      transaction.set(db.collection("usernames").doc(previous), {
        uid,
        username: previous,
        status: "retained",
        current: false,
        retainedReason: "username_changed",
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    }
    transaction.set(targetRef, {
      uid,
      username: decision.username,
      status: "active",
      current: true,
      claimedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    transaction.set(userRef, {
      username: decision.username,
      usernameCanonical: decision.username,
      usernameUpdatedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    const riderUsernamePatch = {
      username: decision.username,
      canonicalUsername: decision.username,
      usernameUpdatedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    };
    if (riderSnapshot.exists) {
      transaction.set(riderRef, riderUsernamePatch, {merge: true});
    }
    if (riderProfileSnapshot.exists) {
      transaction.set(riderProfileRef, riderUsernamePatch, {merge: true});
    }
    transaction.set(db.collection("senderProfileEvents").doc(), {
      uid,
      action: previous ? "sender_username_changed" : "sender_username_claimed",
      previousUsername: previous || null,
      username: decision.username,
      source: "claimSenderUsername",
      createdAt: FieldValue.serverTimestamp(),
    });
  });
  return {ok: true, username: decision.username};
}

module.exports = {
  claimSenderUsername: functions.runWith({enforceAppCheck: true}).https.onCall(claimUsername),
  claimCircumUsername: functions.runWith({enforceAppCheck: true}).https.onCall(claimUsername),
  _test: {normalizeUsername, validateUsername, claimUsername},
};
