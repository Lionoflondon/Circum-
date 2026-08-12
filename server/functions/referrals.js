/* eslint-disable max-len, require-jsdoc */
"use strict";

const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {getAuth} = require("firebase-admin/auth");
const rothLedger = require("./roth-ledger");
const communicationEngine = require("./communication-engine");
const {BALANCE_TYPES, TRANSACTION_TYPES} = require("./roth-ledger-core");
const {
  DEFAULT_REFERRAL_REWARD_ROTH,
  REFERRAL_STATUSES,
  referralRewardFinanceMetadata,
} = require("./referral-core");

const DEFAULT_REWARD = DEFAULT_REFERRAL_REWARD_ROTH;
const REFERRAL_HISTORY_PAGE_SIZE = 20;
const APPROVED_QUALIFYING_EVENTS = new Set([
  "sender_completed_paid_booking",
  "rider_completed_delivery",
  "gift_request_completed",
  "health_plus_completed",
]);

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
  const authUser = await getAuth().getUser(uid);
  const currentUser = await userRef.get();
  const reservedCode = normalizeCode(currentUser.data() && currentUser.data().referralCode);
  if (reservedCode) {
    const reservedRef = db.collection("referralCodes").doc(reservedCode);
    await db.runTransaction(async (transaction) => {
      const reservation = await transaction.get(reservedRef);
      if (reservation.exists && reservation.data().userId !== uid) {
        throw new functions.https.HttpsError("failed-precondition", "Referral code reservation is inconsistent.");
      }
      transaction.set(reservedRef, {
        code: reservedCode,
        userId: uid,
        userEmail: normalizeEmail(authUser.email),
        createdAt: reservation.exists ? reservation.data().createdAt : FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    });
    return {referralCode: reservedCode, referralLink: `https://circumuk.com/join/${reservedCode}`};
  }
  let code = codeFromUser(authUser);
  for (let attempt = 0; attempt < 5; attempt++) {
    const codeRef = db.collection("referralCodes").doc(code);
    try {
      let canonicalCode = code;
      await db.runTransaction(async (transaction) => {
        const [userSnap, codeSnap] = await Promise.all([
          transaction.get(userRef),
          transaction.get(codeRef),
        ]);
        const existing = normalizeCode(userSnap.data() && userSnap.data().referralCode);
        if (existing) {
          canonicalCode = existing;
          return;
        }
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
      return {referralCode: canonicalCode, referralLink: `https://circumuk.com/join/${canonicalCode}`};
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
  const selfReferral = referrerUserId === referredUserId ||
    (referrerEmail && referrerEmail === referredEmail);
  let resultStatus = selfReferral ? REFERRAL_STATUSES.rejected : REFERRAL_STATUSES.signedUp;
  await db.runTransaction(async (transaction) => {
    const referralRef = db.collection("referrals").doc(referralId);
    const existing = await transaction.get(referralRef);
    if (existing.exists) {
      resultStatus = existing.data().status;
      return;
    }
    if (selfReferral) {
      transaction.create(referralRef, {
        referrerUserId,
        referredUserId,
        referralCode: code,
        status: REFERRAL_STATUSES.rejected,
        rewardStatus: REFERRAL_STATUSES.rejected,
        rejectionReason: "Self-referral blocked.",
        createdAt: FieldValue.serverTimestamp(),
        rejectedAt: FieldValue.serverTimestamp(),
      });
      return;
    }
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
  return {status: resultStatus};
});

exports.activateReferral = functions.runWith({enforceAppCheck: true}).https.onCall(async (_data, context) => {
  requireAuth(context);
  throw new functions.https.HttpsError(
      "permission-denied",
      "Referral rewards are issued automatically after a verified qualifying activity.",
  );
});

async function activateReferralForUser({referredUserId, activityType, activityId, userEmail = ""}) {
  if (!APPROVED_QUALIFYING_EVENTS.has(activityType) || !`${activityId || ""}`.trim()) {
    throw new Error("Referral qualification requires an approved canonical activity.");
  }
  const db = getFirestore();
  const referralRef = db.collection("referrals").doc(referredUserId);
  const snap = await referralRef.get();
  if (!snap.exists || snap.data().status === REFERRAL_STATUSES.rothAwarded || snap.data().status === "rewarded" || snap.data().status === "rejected") {
    return {status: snap.exists ? snap.data().status : "none"};
  }
  const referral = snap.data();
  if (referral.referrerUserId === referredUserId) return {status: "rejected"};
  const reward = DEFAULT_REWARD;
  try {
    let qualificationClaimed = false;
    await db.runTransaction(async (transaction) => {
      const latest = await transaction.get(referralRef);
      if (!latest.exists) return;
      const current = latest.data();
      if (current.status === REFERRAL_STATUSES.rothAwarded || current.status === "rewarded" ||
          current.status === REFERRAL_STATUSES.rejected) return;
      if (current.status === REFERRAL_STATUSES.firstQualifyingDeliveryCompleted) {
        qualificationClaimed = current.qualifyingActivityId === activityId &&
          current.qualifyingActivityType === activityType;
        return;
      }
      if (current.status !== REFERRAL_STATUSES.signedUp) return;
      qualificationClaimed = true;
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
    if (!qualificationClaimed) {
      const current = await referralRef.get();
      return {status: current.exists ? current.data().status : "none"};
    }
    const rewardIdentity = `${referredUserId}_${activityId}`;
    await rothLedger.recordRothMovement({
      db,
      userId: referral.referrerUserId,
      userEmail: referral.referrerEmail,
      amount: reward,
      balanceType: BALANCE_TYPES.rothCredit,
      type: TRANSACTION_TYPES.referralReward,
      reason: "Referral activated after first completed activity",
      relatedEntityId: referredUserId,
      transactionId: `referral_reward_${rewardIdentity}_referrer`,
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
      transactionId: `referral_reward_${rewardIdentity}_referred`,
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
    await Promise.all([
      communicationEngine.emitNotification({
        recipientId: referral.referrerUserId,
        recipientRole: "sender",
        type: "referral_reward_issued",
        title: "Referral reward added",
        body: `${reward} Roth has been added to your Wallet.`,
        data: {referralId: referredUserId, role: "inviter"},
      }),
      communicationEngine.emitNotification({
        recipientId: referredUserId,
        recipientRole: "sender",
        type: "referral_welcome_reward_issued",
        title: "Welcome reward added",
        body: `${reward} Roth has been added to your Wallet.`,
        data: {referralId: referredUserId, role: "referred_user"},
      }),
    ]);
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

exports.getReferralDashboard = functions.runWith({enforceAppCheck: true}).https.onCall(async (data, context) => {
  requireAuth(context);
  const uid = context.auth.uid;
  const requestedPageSize = Number(data && data.pageSize || REFERRAL_HISTORY_PAGE_SIZE);
  const pageSize = Number.isFinite(requestedPageSize) ?
    Math.min(50, Math.max(1, Math.floor(requestedPageSize))) : REFERRAL_HISTORY_PAGE_SIZE;
  const cursor = `${data && data.pageToken || ""}`.trim();
  const db = getFirestore();
  const userSnap = await db.collection("users").doc(uid).get();
  const code = normalizeCode(userSnap.data() && userSnap.data().referralCode);
  let query = db.collection("referrals")
      .where("referrerUserId", "==", uid)
      .orderBy("createdAt", "desc")
      .orderBy("__name__", "desc")
      .limit(pageSize + 1);
  if (cursor) {
    const cursorSnap = await db.collection("referrals").doc(cursor).get();
    if (!cursorSnap.exists || cursorSnap.data().referrerUserId !== uid) {
      throw new functions.https.HttpsError("invalid-argument", "Referral history cursor is invalid.");
    }
    query = query.startAfter(cursorSnap);
  }
  const snapshot = await query.get();
  const docs = snapshot.docs.slice(0, pageSize);
  return {
    referralCode: code || null,
    referralLink: code ? `https://circumuk.com/join/${code}` : null,
    referrals: docs.map((doc) => {
      const value = doc.data();
      return {
        referralId: doc.id,
        status: value.status || REFERRAL_STATUSES.invited,
        rewardStatus: value.rewardStatus || value.status || REFERRAL_STATUSES.invited,
        rewardAmount: Number(value.rewardAmount || DEFAULT_REWARD),
        rewardCurrency: "ROTH",
        createdAt: value.createdAt || null,
        qualifiedAt: value.activatedAt || null,
        rewardedAt: value.rewardedAt || null,
      };
    }),
    nextPageToken: snapshot.docs.length > pageSize ? docs[docs.length - 1].id : null,
  };
});

function becameCompleted(before, after, completedStatuses = ["completed", "delivered"]) {
  const was = `${before.status || before.giftStatus || ""}`.toLowerCase();
  const now = `${after.status || after.giftStatus || ""}`.toLowerCase();
  return !completedStatuses.includes(was) && completedStatuses.includes(now);
}

exports.activateReferralOnDeliveryCompleted = functions.firestore
    .document("deliveryRequests/{deliveryId}")
    .onUpdate(async (change, context) => {
      const before = change.before.data() || {};
      const after = change.after.data() || {};
      if (!becameCompleted(before, after, ["completed", "delivered"])) return null;
      const payment = `${after.paymentStatus || ""}`.toLowerCase();
      if (!["paid", "succeeded", "success"].includes(payment)) return null;
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
      if (!becameCompleted(before, after, ["completed", "delivered"])) return null;
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
      if (!becameCompleted(before, after, ["completed", "delivered"])) return null;
      if (!["paid", "succeeded", "success"].includes(`${after.paymentStatus || ""}`.toLowerCase())) return null;
      const userId = `${after.senderId || after.userId || after.profileId || ""}`;
      if (!userId) return null;
      return activateReferralForUser({
        referredUserId: userId,
        activityType: "health_plus_completed",
        activityId: context.params.pickupId,
        userEmail: after.email,
      });
    });

exports._private = {becameCompleted};
