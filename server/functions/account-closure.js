/* eslint-disable max-len, require-jsdoc */
const functions = require("firebase-functions/v1");
const {getAuth} = require("firebase-admin/auth");
const {
  FieldValue,
  getFirestore,
} = require("firebase-admin/firestore");
const giftVoiceMedia = require("./gift-voice-media");

const ACTIVE_DELIVERY_STATUSES = [
  "accepted",
  "assigned",
  "travelling_to_pickup",
  "arrived_at_pickup",
  "waiting_at_pickup",
  "item_verification",
  "collected",
  "travelling_to_dropoff",
  "arrived_at_dropoff",
  "awaiting_pin",
  "in_progress",
  "active",
  "pending",
];

const DISPUTE_STATUSES = ["open", "pending", "under_review", "active"];
const PAYOUT_REVIEW_STATUSES = ["requested", "processing", "under_review"];
const PAYMENT_PENDING_STATUSES = ["pending", "processing", "requires_action"];

function assertRecentAuthentication(context) {
  const authTime = Number(context.auth && context.auth.token && context.auth.token.auth_time);
  const nowSeconds = Math.floor(Date.now() / 1000);
  if (!authTime || nowSeconds - authTime > 300) {
    throw new functions.https.HttpsError(
        "failed-precondition",
        "Please sign in again before closing your account.",
    );
  }
}

async function queryAny(collection, field, op, value) {
  const snapshot = await getFirestore()
      .collection(collection)
      .where(field, op, value)
      .limit(1)
      .get();
  return !snapshot.empty;
}

async function senderHasBlocker(uid) {
  const activeDelivery = await queryAny(
      "deliveryRequests",
      "userId",
      "==",
      uid,
  );
  if (activeDelivery) {
    const snapshot = await getFirestore()
        .collection("deliveryRequests")
        .where("userId", "==", uid)
        .where("status", "in", ACTIVE_DELIVERY_STATUSES.slice(0, 10))
        .limit(1)
        .get();
    if (!snapshot.empty) return "active_delivery";
  }

  const dispute = await getFirestore()
      .collection("disputes")
      .where("senderId", "==", uid)
      .where("status", "in", DISPUTE_STATUSES)
      .limit(1)
      .get();
  if (!dispute.empty) return "open_dispute";

  const payment = await getFirestore()
      .collection("payments")
      .where("senderId", "==", uid)
      .where("status", "in", PAYMENT_PENDING_STATUSES)
      .limit(1)
      .get();
  if (!payment.empty) return "pending_payment";

  return null;
}

async function riderHasBlocker(uid) {
  const activeDelivery = await getFirestore()
      .collection("deliveryRequests")
      .where("riderId", "==", uid)
      .where("status", "in", ACTIVE_DELIVERY_STATUSES.slice(0, 10))
      .limit(1)
      .get();
  if (!activeDelivery.empty) return "active_delivery";

  const dispute = await getFirestore()
      .collection("disputes")
      .where("riderId", "==", uid)
      .where("status", "in", DISPUTE_STATUSES)
      .limit(1)
      .get();
  if (!dispute.empty) return "open_dispute";

  const payout = await getFirestore()
      .collection("payoutRequests")
      .where("riderId", "==", uid)
      .where("status", "in", PAYOUT_REVIEW_STATUSES)
      .limit(1)
      .get();
  if (!payout.empty) return "outstanding_payout_review";

  return null;
}

function blockerMessage(accountType, blocker) {
  if (accountType === "rider") {
    return "Your account cannot be closed while operational activity is still in progress.";
  }
  if (blocker === "pending_payment") {
    return "Your account cannot be closed while a payment is still pending.";
  }
  if (blocker === "open_dispute") {
    return "Your account cannot be closed while a dispute is open.";
  }
  return "Your account cannot be closed while a delivery is still in progress.";
}

async function deleteCollectionDocs(collection, field, uid, batch) {
  const snapshot = await getFirestore()
      .collection(collection)
      .where(field, "==", uid)
      .limit(100)
      .get();
  snapshot.docs.forEach((doc) => batch.delete(doc.ref));
}

async function closeAccount(data, context) {
  if (!context.auth || !context.auth.uid) {
    throw new functions.https.HttpsError(
        "unauthenticated",
        "Sign in before closing your account.",
    );
  }
  assertRecentAuthentication(context);

  const uid = context.auth.uid;
  const accountType = `${data && data.accountType || ""}`.trim();
  if (accountType !== "sender" && accountType !== "rider") {
    throw new functions.https.HttpsError(
        "invalid-argument",
        "Choose a valid account type.",
    );
  }

  const blocker = accountType === "rider" ?
    await riderHasBlocker(uid) :
    await senderHasBlocker(uid);
  if (blocker) {
    throw new functions.https.HttpsError(
        "failed-precondition",
        blockerMessage(accountType, blocker),
        {blocker},
    );
  }

  const db = getFirestore();
  const batch = db.batch();
  const timestamp = FieldValue.serverTimestamp();
  const closure = {
    uid,
    accountType,
    status: "closed",
    closedAt: timestamp,
    initiatedBy: uid,
    retainedRecords:
      "Financial, fraud-prevention, compliance and completed-delivery records may be retained where required.",
  };

  batch.set(db.collection("accountClosureAudit").doc(), closure);
  batch.set(db.collection("closedAccounts").doc(uid), closure, {merge: true});

  const profileCollections = accountType === "rider" ?
    ["riders", "riderProfiles", "riderPresence"] :
    ["users", "senderProfiles", "senderPresence"];
  profileCollections.forEach((collection) => {
    batch.set(db.collection(collection).doc(uid), {
      accountClosed: true,
      closedAt: timestamp,
      displayName: FieldValue.delete(),
      fullName: FieldValue.delete(),
      firstName: FieldValue.delete(),
      lastName: FieldValue.delete(),
      phone: FieldValue.delete(),
      phoneNumber: FieldValue.delete(),
      email: FieldValue.delete(),
      address: FieldValue.delete(),
      homeAddress: FieldValue.delete(),
      photoURL: FieldValue.delete(),
      photoUrl: FieldValue.delete(),
      profilePhotoUrl: FieldValue.delete(),
      profileThumbnailUrl: FieldValue.delete(),
      profilePhotoPath: FieldValue.delete(),
      profileThumbnailPath: FieldValue.delete(),
      profilePhotoVersion: FieldValue.delete(),
      profilePhotoMetadata: FieldValue.delete(),
      profilePhoto: FieldValue.delete(),
      notificationTokens: FieldValue.delete(),
      fcmToken: FieldValue.delete(),
      apnsToken: FieldValue.delete(),
      preferences: FieldValue.delete(),
      accessibilitySettings: FieldValue.delete(),
    }, {merge: true});
  });

  await deleteCollectionDocs("notificationTokens", "uid", uid, batch);
  await deleteCollectionDocs("savedAddresses", "userId", uid, batch);
  await deleteCollectionDocs("senderSavedAddresses", "userId", uid, batch);
  await deleteCollectionDocs("draftBookings", "userId", uid, batch);
  await deleteCollectionDocs("riderDrafts", "riderId", uid, batch);
  if (accountType === "sender") {
    await giftVoiceMedia.cleanupGiftVoiceMediaForAccount({db, uid, batch});
  }

  await batch.commit();

  await getAuth().revokeRefreshTokens(uid);
  await getAuth().deleteUser(uid);

  return {status: "closed"};
}

module.exports = {
  closeAccount: functions.region("us-central1").https.onCall(closeAccount),
  _test: {
    ACTIVE_DELIVERY_STATUSES,
    blockerMessage,
  },
};
