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

exports.ensureReferralCode = functions.https.onCall(async (data, context) => {
  requireAuth(context);
  const db = getFirestore();
  const uid = context.auth.uid;
  const userRef = db.collection("users").doc(uid);
  const snap = await userRef.get();
  const sender = snap.data() || {};
  const roles = [...(Array.isArray(sender.roles) ? sender.roles : []), sender.role, sender.userType, sender.accountType];
  const isSender = roles.some((role) => ["sender", "user", "customer"].includes(`${role || ""}`.toLowerCase()));
  if (!isSender && (await riderReferralProfile(db, uid)).exists) {
    return ensureRiderReferralCode(data, context);
  }
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

async function riderReferralProfile(db, uid, transaction = null) {
  const read = (ref) => transaction ? transaction.get(ref) : ref.get();
  const [profile, rider] = await Promise.all([read(db.doc(`riderProfiles/${uid}`)), read(db.doc(`riders/${uid}`))]);
  return {exists: profile.exists || rider.exists, data: {...profile.data(), ...rider.data()}};
}
function riderReferralEligible(profile) {
  const {riderApproved} = require("./rider-presence-core");
  return riderApproved(profile) && !profile.isSuspended && !profile.isFrozen && !profile.isClosed &&
    !["suspended", "frozen", "closed", "rejected"].includes(`${profile.riderStatus || ""}`.toLowerCase());
}
async function ensureRiderReferralCode(_data, context) {
  requireAuth(context);
  const db = getFirestore(); const uid = context.auth.uid;
  const email = normalizeEmail(context.auth.token.email || await userEmail(uid));
  const code = `R${require("node:crypto").createHash("sha256").update(uid).digest("hex").slice(0, 23)}`.toUpperCase();
  return db.runTransaction(async (transaction) => {
    const profile = await riderReferralProfile(db, uid, transaction);
    if (!profile.exists || !riderReferralEligible(profile.data)) {
      throw new functions.https.HttpsError("permission-denied", "Rider approval is required to share a referral code.");
    }
    const ref = db.doc(`referralCodes/${code}`); const existing = await transaction.get(ref);
    if (existing.exists && existing.data().userId !== uid) throw new functions.https.HttpsError("already-exists", "Referral code collision. Contact support.");
    const link = `https://circumuk.com/rider?referral=${code}`;
    if (!existing.exists) transaction.set(ref, {code, userId: uid, userEmail: email, program: "rider", createdAt: FieldValue.serverTimestamp()});
    transaction.set(db.doc(`riderProfiles/${uid}`), {riderReferralCode: code, riderReferralLink: link}, {merge: true});
    return {referralCode: code, referralLink: link, rewardAmount: 5, rewardCurrency: "ROTH", rewardSource: "Referral"};
  });
}
exports.ensureRiderReferralCode = functions.https.onCall(ensureRiderReferralCode);

exports.attachReferralCode = functions.https.onCall(async (data, context) => {
  requireAuth(context);
  if (!data || typeof data !== "object" || typeof data.referralCode !== "string" || data.referralCode.length > 256) {
    throw new functions.https.HttpsError("invalid-argument", "Supply a referral code string.");
  }
  const code = normalizeCode(data.referralCode);
  if (!code) return {status: "invalid"};
  const db = getFirestore();
  const referredUserId = context.auth.uid;
  const referredEmail = normalizeEmail(context.auth.token.email || await userEmail(referredUserId));
  const codeRef = db.collection("referralCodes").doc(code);
  const preliminary = await codeRef.get();
  const owner = preliminary.exists && preliminary.data().userId;
  const fallbackEmail = owner && !preliminary.data().userEmail ? await userEmail(owner) : "";
  return db.runTransaction(async (transaction) => {
    const referralRef = db.collection("referrals").doc(referredUserId);
    const existing = await transaction.get(referralRef);
    if (existing.exists && !["rejected", "REJECTED"].includes(existing.data().status)) {
      return {status: "already_attached"};
    }
    const codeSnap = await transaction.get(codeRef);
    if (!codeSnap.exists) return {status: "not_found"};
    const riderProgram = codeSnap.data().program === "rider";
    if (data.program === "rider" && !riderProgram) return {status: "not_found"};
    if (riderProgram) {
      const profile = await riderReferralProfile(db, referredUserId, transaction);
      if (!profile.exists) return {status: "invalid"};
    }
    const referrerUserId = codeSnap.data().userId;
    if (typeof referrerUserId !== "string" || !referrerUserId) return {status: "invalid"};
    const referrerEmail = normalizeEmail(codeSnap.data().userEmail || (referrerUserId === owner ? fallbackEmail : ""));
    const self = referrerUserId === referredUserId || (referrerEmail && referrerEmail === referredEmail);
    const status = self ? "rejected" : REFERRAL_STATUSES.signedUp;
    transaction.set(referralRef, {
      referrerUserId,
      inviterUserId: referrerUserId,
      referrerEmail,
      referredUserId,
      referredEmail,
      referralCode: code,
      ...(riderProgram ? {program: "rider"} : {}),
      status,
      rewardStatus: self ? REFERRAL_STATUSES.rejected : status,
      rewardAmount: self ? 0 : DEFAULT_REWARD,
      rewardCurrency: "ROTH",
      rewardSource: "Referral",
      createdAt: existing.exists ? existing.data().createdAt || FieldValue.serverTimestamp() : FieldValue.serverTimestamp(),
      signedUpAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      ...(self ? {rejectionReason: "Self-referral blocked.", rejectedAt: FieldValue.serverTimestamp()} : {}),
    });
    if (self) return {status: "rejected_self_referral"};
    transaction.set(db.collection("users").doc(referredUserId), {
      referredBy: referrerUserId,
      referralCodeUsed: code,
      referralProgramStatus: REFERRAL_STATUSES.signedUp,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    return {status: "applied"};
  });
});

exports.activateReferral = functions.https.onCall(async (_, context) => {
  requireAuth(context);
  throw new functions.https.HttpsError(
      "permission-denied",
      "Referral activation is only available from verified backend completion events.",
  );
});

const QUALIFYING_TERMINAL_STATES = new Set(["completed", "delivered"]);
const PAID_STATES = new Set(["paid", "succeeded", "success"]);

async function loadQualifyingActivity({referredUserId, activityType, activityId}) {
  const collections = {
    sender_completed_paid_booking: "deliveryRequests",
    rider_completed_delivery: "deliveryRequests",
    gift_request_completed: "giftRequests",
    health_plus_completed: "prescriptionPickups",
  };
  const collection = collections[activityType];
  if (!collection || !activityId) return null;
  const snap = await getFirestore().collection(collection).doc(activityId).get();
  if (!snap.exists) return null;
  const activity = snap.data() || {};
  const ownerId = activityType === "rider_completed_delivery" ?
    (activity.riderId || activity.assignedRiderId) :
    (activity.senderId || activity.userId || activity.profileId);
  const status = `${activity.status || activity.deliveryStatus || activity.giftStatus || ""}`.toLowerCase();
  const payment = `${activity.paymentStatus || ""}`.toLowerCase();
  const refund = `${activity.refundStatus || ""}`.toLowerCase();
  if (`${ownerId || ""}` !== referredUserId ||
      !QUALIFYING_TERMINAL_STATES.has(status) ||
      (collection !== "deliveryRequests" && status !== "completed") ||
      !PAID_STATES.has(payment) ||
      ["refunded", "partially_refunded", "failed", "cancelled", "canceled"].includes(refund)) {
    return null;
  }
  return activity;
}

async function activateReferralForUser({referredUserId, activityType, activityId, userEmail = ""}) {
  const activity = await loadQualifyingActivity({referredUserId, activityType, activityId});
  if (!activity) return {status: "not_qualifying"};
  const db = getFirestore();
  const referralRef = db.collection("referrals").doc(referredUserId);
  const snap = await referralRef.get();
  if (!snap.exists || snap.data().status === REFERRAL_STATUSES.rothAwarded || snap.data().status === "rewarded" || snap.data().status === "rejected") {
    return {status: snap.exists ? snap.data().status : "none"};
  }
  const referral = snap.data();
  if (referral.program === "rider" && activityType !== "rider_completed_delivery") return {status: "not_qualifying"};
  if (activityType === "rider_completed_delivery") {
    const profile = await riderReferralProfile(db, referredUserId);
    if (!profile.exists || !riderReferralEligible(profile.data)) return {status: "not_qualifying"};
  }
  if (referral.referrerUserId === referredUserId) return {status: "rejected"};
  const reward = DEFAULT_REWARD;
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
      rewardSource: "Referral",
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
  return !QUALIFYING_TERMINAL_STATES.has(was) && QUALIFYING_TERMINAL_STATES.has(now);
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
