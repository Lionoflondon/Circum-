/* eslint-disable max-len, require-jsdoc */
"use strict";

const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {getAuth} = require("firebase-admin/auth");
const rothLedger = require("./roth-ledger");
const {BALANCE_TYPES, TRANSACTION_TYPES} = require("./roth-ledger-core");
const {
  DEFAULT_REFERRAL_REWARD_ROTH,
  REFERRAL_STATUSES,
  referralRewardFinanceMetadata,
} = require("./referral-core");

const DEFAULT_REWARD = DEFAULT_REFERRAL_REWARD_ROTH;

function requireAuth(context) {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in to use referrals.");
  }
}

function normalizeCode(code) {
  return `${code || ""}`.trim().toUpperCase().replace(/[^A-Z0-9]/g, "").slice(0, 24);
}

function normalizeEmail(email) {
  return `${email || ""}`.trim().toLowerCase();
}

async function userEmail(uid) {
  try {
    return normalizeEmail((await getAuth().getUser(uid)).email);
  } catch (_) {
    return "";
  }
}

function codeFromUser(user) {
  const source = normalizeEmail(user.email).split("@")[0].replace(/[^a-z0-9]/gi, "").toUpperCase();
  return `${source || "CIRCUM"}${user.uid.slice(0, 4).toUpperCase()}`.slice(0, 12);
}

exports.ensureReferralCode = functions.runWith({enforceAppCheck: true}).https.onCall(async (data, context) => {
  requireAuth(context);
  const db = getFirestore();
  const uid = context.auth.uid;
  const userRef = db.collection("users").doc(uid);
  const snap = await userRef.get();
  const existing = normalizeCode(snap.data() && snap.data().referralCode);
  if (existing) {
    return {referralCode: existing, referralLink: `https://circumuk.com/join/${existing}`};
  }
  const authUser = await getAuth().getUser(uid);
  let code = codeFromUser(authUser);
  for (let attempt = 0; attempt < 5; attempt++) {
    const codeRef = db.collection("referralCodes").doc(code);
    try {
      await db.runTransaction(async (transaction) => {
        const codeSnap = await transaction.get(codeRef);
        if (codeSnap.exists && codeSnap.data().userId !== uid) throw new Error("collision");
        transaction.set(codeRef, {
          code,
          userId: uid,
          userEmail: normalizeEmail(authUser.email),
          createdAt: FieldValue.serverTimestamp(),
        }, {merge: true});
        transaction.set(userRef, {
          referralCode: code,
          referralLink: `https://circumuk.com/join/${code}`,
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
      });
      return {referralCode: code, referralLink: `https://circumuk.com/join/${code}`};
    } catch (error) {
      code = `${codeFromUser(authUser).slice(0, 8)}${Math.floor(Math.random() * 9000) + 1000}`;
    }
  }
  throw new functions.https.HttpsError("already-exists", "Could not create a unique referral code.");
});

exports.attachReferralCode = functions.runWith({enforceAppCheck: true}).https.onCall(async (data, context) => {
  requireAuth(context);
  const code = normalizeCode(data.referralCode);
  if (!code) throw new functions.https.HttpsError("invalid-argument", "Referral code is required.");
  const db = getFirestore();
  const codeSnap = await db.collection("referralCodes").doc(code).get();
  if (!codeSnap.exists) {
    throw new functions.https.HttpsError("not-found", "Referral code was not found.");
  }
  const referrerUserId = codeSnap.data().userId;
  const referredUserId = context.auth.uid;
  const referrerEmail = normalizeEmail(codeSnap.data().userEmail || await userEmail(referrerUserId));
  const referredEmail = normalizeEmail(context.auth.token.email || await userEmail(referredUserId));
  const referralId = referredUserId;
  if (referrerUserId === referredUserId || (referrerEmail && referrerEmail === referredEmail)) {
    await db.collection("referrals").doc(referralId).set({
      referrerUserId,
      referredUserId,
      referralCode: code,
      status: "rejected",
      rejectionReason: "Self-referral blocked.",
      createdAt: FieldValue.serverTimestamp(),
      rejectedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    return {status: "rejected"};
  }
  await db.runTransaction(async (transaction) => {
    const referralRef = db.collection("referrals").doc(referralId);
    const existing = await transaction.get(referralRef);
    if (existing.exists) return;
    transaction.set(referralRef, {
      referrerUserId,
      inviterUserId: referrerUserId,
      referrerEmail,
      referredUserId,
      referredEmail,
      referralCode: code,
      status: REFERRAL_STATUSES.signedUp,
      rewardStatus: REFERRAL_STATUSES.signedUp,
      rewardAmount: DEFAULT_REWARD,
      rewardCurrency: "ROTH",
      rewardSource: "Referral",
      createdAt: FieldValue.serverTimestamp(),
      signedUpAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.set(db.collection("users").doc(referredUserId), {
      referredBy: referrerUserId,
      referralCodeUsed: code,
      referralProgramStatus: REFERRAL_STATUSES.signedUp,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  });
  return {status: REFERRAL_STATUSES.signedUp};
});

exports.activateReferral = functions.runWith({enforceAppCheck: true}).https.onCall(async (data, context) => {
  requireAuth(context);
  const referredUserId = `${data.referredUserId || context.auth.uid}`.trim();
  if (referredUserId !== context.auth.uid && !context.auth.token.admin) {
    throw new functions.https.HttpsError("permission-denied", "Cannot activate another user's referral.");
  }
  const activityType = `${data.activityType || "activity"}`.trim();
  const activityId = `${data.activityId || ""}`.trim();
  return activateReferralForUser({
    referredUserId,
    activityType,
    activityId,
    userEmail: context.auth.token.email,
  });
});

async function activateReferralForUser({referredUserId, activityType, activityId, userEmail = ""}) {
  const db = getFirestore();
  const referralRef = db.collection("referrals").doc(referredUserId);
  const snap = await referralRef.get();
  if (!snap.exists || snap.data().status === REFERRAL_STATUSES.rothAwarded || snap.data().status === "rewarded" || snap.data().status === "rejected") {
    return {status: snap.exists ? snap.data().status : "none"};
  }
  const referral = snap.data();
  if (referral.referrerUserId === referredUserId) return {status: "rejected"};
  const reward = Number(referral.rewardAmount || DEFAULT_REWARD);
  try {
    await db.runTransaction(async (transaction) => {
      const latest = await transaction.get(referralRef);
      if (!latest.exists || latest.data().status === REFERRAL_STATUSES.rothAwarded || latest.data().status === "rewarded") return;
      transaction.set(referralRef, {
        status: REFERRAL_STATUSES.firstQualifyingDeliveryCompleted,
        rewardStatus: REFERRAL_STATUSES.firstQualifyingDeliveryCompleted,
        qualifyingActivityType: activityType,
        qualifyingActivityId: activityId || null,
        qualifyingDeliveryId: activityId || null,
        activatedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    });
    await rothLedger.recordRothMovement({
      db,
      userId: referral.referrerUserId,
      userEmail: referral.referrerEmail,
      amount: reward,
      balanceType: BALANCE_TYPES.rothCredit,
      type: TRANSACTION_TYPES.referralReward,
      reason: "Referral activated after first completed activity",
      relatedEntityId: referredUserId,
      transactionId: `referral_reward_${referredUserId}_referrer`,
      metadata: referralRewardFinanceMetadata({
        referralCode: referral.referralCode,
        inviterUserId: referral.referrerUserId,
        referredUserId,
        rewardAmount: reward,
        rewardStatus: REFERRAL_STATUSES.rothAwarded,
        activityType,
        activityId,
        role: "inviter",
      }),
    });
    await rothLedger.recordRothMovement({
      db,
      userId: referredUserId,
      userEmail: referral.referredEmail || userEmail,
      amount: reward,
      balanceType: BALANCE_TYPES.rothCredit,
      type: TRANSACTION_TYPES.referralWelcomeReward,
      reason: "Joined through referral and completed first activity",
      relatedEntityId: referredUserId,
      transactionId: `referral_reward_${referredUserId}_referred`,
      metadata: referralRewardFinanceMetadata({
        referralCode: referral.referralCode,
        inviterUserId: referral.referrerUserId,
        referredUserId,
        rewardAmount: reward,
        rewardStatus: REFERRAL_STATUSES.rothAwarded,
        activityType,
        activityId,
        role: "referred_user",
      }),
    });
    await referralRef.set({
      status: REFERRAL_STATUSES.rothAwarded,
      rewardStatus: REFERRAL_STATUSES.rothAwarded,
      rewardAmount: reward,
      rewardCurrency: "ROTH",
      inviterUserId: referral.referrerUserId,
      referredUserId,
      rewardedAt: FieldValue.serverTimestamp(),
      rewardIssuedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    return {status: REFERRAL_STATUSES.rothAwarded, rewardAmount: reward};
  } catch (error) {
    console.error("Referral activation failed", error);
    await referralRef.set({
      status: REFERRAL_STATUSES.firstQualifyingDeliveryCompleted,
      rewardStatus: REFERRAL_STATUSES.review,
      needsReview: true,
      reviewReason: error.message,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    return {status: "review"};
  }
}

function becameCompleted(before, after) {
  const was = `${before.status || before.giftStatus || ""}`.toLowerCase();
  const now = `${after.status || after.giftStatus || ""}`.toLowerCase();
  return !["completed", "delivered", "active"].includes(was) &&
    ["completed", "delivered", "active"].includes(now);
}

exports.activateReferralOnDeliveryCompleted = functions.firestore
    .document("deliveryRequests/{deliveryId}")
    .onUpdate(async (change, context) => {
      const before = change.before.data() || {};
      const after = change.after.data() || {};
      if (!becameCompleted(before, after)) return null;
      const payment = `${after.paymentStatus || ""}`.toLowerCase();
      if (payment && !["paid", "succeeded", "success"].includes(payment)) return null;
      const deliveryId = context.params.deliveryId;
      const senderId = `${after.senderId || after.userId || ""}`;
      const riderId = `${after.riderId || after.assignedRiderId || ""}`;
      await Promise.all([
        senderId ? activateReferralForUser({referredUserId: senderId, activityType: "sender_completed_paid_booking", activityId: deliveryId, userEmail: after.senderEmail}) : null,
        riderId ? activateReferralForUser({referredUserId: riderId, activityType: "rider_completed_delivery", activityId: deliveryId, userEmail: after.riderEmail}) : null,
      ]);
      return null;
    });

exports.activateReferralOnGiftCompleted = functions.firestore
    .document("giftRequests/{giftRequestId}")
    .onUpdate(async (change, context) => {
      const before = change.before.data() || {};
      const after = change.after.data() || {};
      if (!becameCompleted(before, after)) return null;
      if (`${after.paymentStatus || ""}`.toLowerCase() !== "paid") return null;
      const senderId = `${after.senderId || ""}`;
      if (!senderId) return null;
      return activateReferralForUser({
        referredUserId: senderId,
        activityType: "gift_request_completed",
        activityId: context.params.giftRequestId,
        userEmail: after.senderEmail,
      });
    });

exports.activateReferralOnHealthPlusCompleted = functions.firestore
    .document("prescriptionPickups/{pickupId}")
    .onUpdate(async (change, context) => {
      const before = change.before.data() || {};
      const after = change.after.data() || {};
      if (!becameCompleted(before, after)) return null;
      const userId = `${after.senderId || after.userId || after.profileId || ""}`;
      if (!userId) return null;
      return activateReferralForUser({
        referredUserId: userId,
        activityType: "health_plus_completed",
        activityId: context.params.pickupId,
        userEmail: after.email,
      });
    });
