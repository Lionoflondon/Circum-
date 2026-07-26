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

function cleanMap(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}

function cleanEmail(value) {
  const email = cleanText(value, 180).toLowerCase();
  if (!email || !email.includes("@")) {
    throw new functions.https.HttpsError("invalid-argument", "A valid email is required.");
  }
  return email;
}

function normalizeNotificationIds(value) {
  const raw = Array.isArray(value) ? value : [value];
  return raw
      .map((entry) => cleanText(entry, 160))
      .filter(Boolean)
      .slice(0, 100);
}

function cleanSenderProfilePatch(data, context) {
  const firstName = cleanText(data.firstName, 80);
  const lastName = cleanText(data.lastName, 80);
  const displayName = cleanText(
      data.displayName || data.fullName || data.name ||
      [firstName, lastName].filter(Boolean).join(" "),
      120,
  );
  const username = cleanText(data.username, 60).replace(/^@/, "");
  const phone = cleanText(data.phone || data.phoneNumber, 40);
  const patch = {
    accountType: "sender",
    role: "user",
    userType: "sender",
    status: "active",
    roles: FieldValue.arrayUnion("sender"),
    email: cleanText(context.auth.token && context.auth.token.email, 180),
    updatedAt: FieldValue.serverTimestamp(),
  };
  if (displayName) {
    patch.displayName = displayName;
    patch.fullName = displayName;
    patch.name = displayName;
  }
  if (firstName) patch.firstName = firstName;
  if (lastName) patch.lastName = lastName;
  if (username) patch.username = username;
  if (phone) {
    patch.phone = phone;
    patch.phoneNumber = phone;
  }
  if (data.communicationPreferences && typeof data.communicationPreferences === "object") {
    patch.communicationPreferences = data.communicationPreferences;
  }
  return {
    patch,
    changedFields: Object.keys(patch).filter((key) => !["updatedAt", "roles"].includes(key)),
  };
}

exports.updateSenderProfile = functions.https.onCall(async (data, context) => {
  const uid = requireSender(context);
  const db = getFirestore();
  const ref = db.collection("users").doc(uid);
  const existing = await ref.get();
  const {patch, changedFields} = cleanSenderProfilePatch(data || {}, context);
  if (!existing.exists) patch.createdAt = FieldValue.serverTimestamp();
  await ref.set(patch, {merge: true});
  await db.collection("senderProfileEvents").doc().set({
    uid,
    action: "sender_profile_updated",
    source: "updateSenderProfile",
    changedFields,
    createdAt: FieldValue.serverTimestamp(),
  });
  return {ok: true};
});

exports.ensureSenderAccount = functions.https.onCall(async (data, context) => {
  const uid = requireSender(context);
  const db = getFirestore();
  const userRef = db.collection("users").doc(uid);
  const riderRef = db.collection("riderProfiles").doc(uid);
  const adminRef = db.collection("adminUsers").doc(uid);
  const now = FieldValue.serverTimestamp();

  const result = await db.runTransaction(async (transaction) => {
    const [userSnap, riderSnap, adminSnap] = await Promise.all([
      transaction.get(userRef),
      transaction.get(riderRef),
      transaction.get(adminRef),
    ]);
    const existing = userSnap.exists ? userSnap.data() || {} : {};
    const roles = new Set([
      ...(Array.isArray(existing.roles) ? existing.roles.map((entry) => cleanText(entry, 80).toLowerCase()) : []),
      cleanText(existing.role, 80).toLowerCase(),
      cleanText(existing.userType, 80).toLowerCase(),
      cleanText(existing.accountType, 80).toLowerCase(),
    ].filter(Boolean));
    if (roles.has("admin") || roles.has("rider") || riderSnap.exists || adminSnap.exists) {
      if (roles.has("sender") || roles.has("user") || roles.has("customer")) {
        return {allowed: true, roles: Array.from(roles)};
      }
      return {allowed: false, roles: Array.from(roles)};
    }
    transaction.set(userRef, {
      uid,
      email: cleanText(context.auth.token && context.auth.token.email, 180),
      role: "user",
      roles: FieldValue.arrayUnion("sender"),
      userType: "sender",
      accountType: "sender",
      status: "active",
      createdAt: userSnap.exists ? existing.createdAt || now : now,
      updatedAt: now,
    }, {merge: true});
    transaction.set(db.collection("senderProfileEvents").doc(), {
      uid,
      action: "sender_account_ensured",
      source: "ensureSenderAccount",
      createdAt: now,
    });
    return {allowed: true, roles: ["sender"]};
  });

  return {ok: true, ...result};
});

exports.markSenderLegendCelebrationSeen = functions.https.onCall(async (data, context) => {
  const uid = requireSender(context);
  const profileId = cleanText(data && data.profileId, 160);
  if (profileId && profileId !== uid) {
    throw new functions.https.HttpsError("permission-denied", "You can only update your own recognition view.");
  }
  await getFirestore().collection("users").doc(uid).set({
    legendCelebrationSeenAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  return {ok: true};
});

exports.recordWebsiteVisit = functions.https.onCall(async (data, context) => {
  const input = cleanMap(data);
  const query = cleanMap(input.query);
  const safeQuery = {};
  Object.entries(query).slice(0, 20).forEach(([key, value]) => {
    safeQuery[cleanText(key, 80)] = cleanText(value, 240);
  });
  await getFirestore().collection("websiteVisitors").add({
    url: cleanText(input.url, 1000),
    path: cleanText(input.path, 300),
    query: safeQuery,
    appMode: cleanText(input.appMode, 80),
    userId: context.auth && context.auth.uid || null,
    email: context.auth && context.auth.token && context.auth.token.email || null,
    signedIn: Boolean(context.auth),
    source: "circum-web",
    createdAt: FieldValue.serverTimestamp(),
  });
  return {ok: true};
});

exports.requestSenderEmailChange = functions.https.onCall(async (data, context) => {
  const uid = requireSender(context);
  const pendingEmail = cleanEmail(data.pendingEmail || data.email);
  const db = getFirestore();
  const now = FieldValue.serverTimestamp();
  await db.runTransaction(async (transaction) => {
    transaction.set(db.collection("users").doc(uid), {
      pendingEmail,
      updatedAt: now,
    }, {merge: true});
    transaction.set(db.collection("senderProfileEvents").doc(), {
      uid,
      action: "sender_email_change_requested",
      source: "requestSenderEmailChange",
      pendingEmail,
      createdAt: now,
    });
  });
  return {ok: true};
});

exports.updateSenderLocation = functions.https.onCall(async (data, context) => {
  const uid = requireSender(context);
  const position = data.position || {};
  const latitude = Number(position.latitude || position.lat || position.geopoint && position.geopoint.latitude);
  const longitude = Number(position.longitude || position.lng || position.lon || position.geopoint && position.geopoint.longitude);
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
    throw new functions.https.HttpsError("invalid-argument", "A valid location is required.");
  }
  if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
    throw new functions.https.HttpsError("invalid-argument", "Location is out of range.");
  }
  const patch = {
    position: {
      latitude,
      longitude,
      geohash: cleanText(position.geohash, 120),
    },
    updatedAt: FieldValue.serverTimestamp(),
  };
  await getFirestore().collection("users").doc(uid).set(patch, {merge: true});
  return {ok: true};
});

exports.recordIrisLearningCandidate = functions.https.onCall(async (data, context) => {
  const uid = requireSender(context);
  const description = cleanText(data.description, 1000);
  const matchedItemName = cleanText(data.matchedItemName, 240);
  const userCorrectedWeightKg = Number(data.userCorrectedWeightKg);
  if (!description || !matchedItemName || !Number.isFinite(userCorrectedWeightKg)) {
    throw new functions.https.HttpsError("invalid-argument", "IRIS learning candidate is incomplete.");
  }
  await getFirestore().collection("iris_learning_review_candidates").add({
    senderId: uid,
    description,
    matchedItemName,
    userCorrectedWeightKg,
    irisEstimatedWeightKg: Number(data.irisEstimatedWeightKg) || null,
    deltaKg: Number(data.deltaKg) || null,
    confidence: Number(data.confidence) || null,
    createdAt: FieldValue.serverTimestamp(),
    source: "recordIrisLearningCandidate",
    status: "pending_review",
  });
  return {ok: true};
});

exports.recordIrisLearningOutlier = functions.https.onCall(async (data, context) => {
  const uid = requireSender(context);
  const description = cleanText(data.description, 1000);
  const matchedItemName = cleanText(data.matchedItemName, 240);
  if (!description || !matchedItemName) {
    throw new functions.https.HttpsError("invalid-argument", "IRIS outlier is incomplete.");
  }
  await getFirestore().collection("irisLearningOutliers").add({
    senderId: uid,
    description,
    matchedItemName,
    trustedWeightKg: Number(data.trustedWeightKg) || null,
    outlierWeightsKg: Array.isArray(data.outlierWeightsKg) ?
      data.outlierWeightsKg.map((entry) => Number(entry)).filter(Number.isFinite).slice(0, 20) :
      [],
    reason: cleanText(data.reason || "sender_web_weight_outlier", 120),
    status: "pending_review",
    source: "recordIrisLearningOutlier",
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
