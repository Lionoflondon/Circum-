/* eslint-disable max-len, require-jsdoc */
const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");

function requireSender(context) {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in to continue.");
  }
  return context.auth.uid;
}

function cleanText(value, max = 160) {
  return String(value || "").trim().slice(0, max);
}

function normalizeNotificationIds(value) {
  const raw = Array.isArray(value) ? value : [value];
  return raw
      .map((entry) => cleanText(entry, 160))
      .filter(Boolean)
      .slice(0, 100);
}

exports.updateSenderProfile = functions.https.onCall(async (data, context) => {
  const uid = requireSender(context);
  const displayName = cleanText(data.displayName, 120);
  const username = cleanText(data.username, 60).replace(/^@/, "");
  const phone = cleanText(data.phone, 40);
  if (!displayName) {
    throw new functions.https.HttpsError("invalid-argument", "Display name is required.");
  }
  const db = getFirestore();
  const ref = db.collection("users").doc(uid);
  const existing = await ref.get();
  const patch = {
    displayName,
    username,
    phone,
    email: cleanText(context.auth.token && context.auth.token.email, 180),
    accountType: "sender",
    updatedAt: FieldValue.serverTimestamp(),
  };
  if (!existing.exists) patch.createdAt = FieldValue.serverTimestamp();
  await ref.set(patch, {merge: true});
  await db.collection("senderProfileEvents").doc().set({
    uid,
    action: "sender_profile_updated",
    source: "updateSenderProfile",
    changedFields: ["displayName", "username", "phone"],
    createdAt: FieldValue.serverTimestamp(),
  });
  return {ok: true};
});

exports.updateSenderProfilePhoto = functions.https.onCall(async (data, context) => {
  const uid = requireSender(context);
  const photoURL = cleanText(data.photoURL, 2048);
  if (!photoURL) {
    throw new functions.https.HttpsError("invalid-argument", "Profile photo URL is required.");
  }
  const db = getFirestore();
  await db.collection("users").doc(uid).set({
    photoURL,
    accountType: "sender",
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  await db.collection("senderProfileEvents").doc().set({
    uid,
    action: "sender_profile_photo_updated",
    source: "updateSenderProfilePhoto",
    createdAt: FieldValue.serverTimestamp(),
  });
  return {ok: true, photoURL};
});

exports.updateSenderPushToken = functions.https.onCall(async (data, context) => {
  const uid = requireSender(context);
  const fcmToken = cleanText(data.fcmToken, 4096);
  if (!fcmToken) {
    throw new functions.https.HttpsError("invalid-argument", "Push token is required.");
  }
  const db = getFirestore();
  await db.collection("users").doc(uid).set({
    fcmToken,
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  await db.collection("senderProfileEvents").doc().set({
    uid,
    action: "sender_push_token_updated",
    source: "updateSenderPushToken",
    createdAt: FieldValue.serverTimestamp(),
  });
  return {ok: true};
});

exports.updateSenderNotificationState = functions.https.onCall(async (data, context) => {
  const uid = requireSender(context);
  const action = cleanText(data.action, 40);
  const ids = normalizeNotificationIds(data.notificationIds || data.notificationId);
  if (!ids.length) {
    throw new functions.https.HttpsError("invalid-argument", "Notification id is required.");
  }
  const allowed = new Set(["mark_read", "archive", "delete"]);
  if (!allowed.has(action)) {
    throw new functions.https.HttpsError("invalid-argument", "Unsupported notification action.");
  }
  const db = getFirestore();
  const now = FieldValue.serverTimestamp();
  await db.runTransaction(async (transaction) => {
    const refs = ids.map((id) => db.collection("notifications").doc(id));
    const snaps = await Promise.all(refs.map((ref) => transaction.get(ref)));
    snaps.forEach((snap, index) => {
      if (!snap.exists) {
        throw new functions.https.HttpsError("not-found", "Notification not found.");
      }
      const notification = snap.data() || {};
      if (notification.recipientId !== uid) {
        throw new functions.https.HttpsError("permission-denied", "Notification does not belong to this account.");
      }
      const patch = action === "mark_read" ?
        {read: true, readAt: now} :
        action === "archive" ?
          {archived: true, archivedAt: now} :
          {deletedAt: now};
      transaction.set(refs[index], patch, {merge: true});
    });
    transaction.set(db.collection("senderNotificationEvents").doc(), {
      uid,
      action,
      notificationIds: ids,
      source: "updateSenderNotificationState",
      createdAt: now,
    });
  });
  return {ok: true, notificationIds: ids, action};
});
