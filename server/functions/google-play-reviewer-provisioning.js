"use strict";

const functions = require("firebase-functions/v1");
const {getAuth} = require("firebase-admin/auth");
const {getFirestore, FieldValue, Timestamp} = require("firebase-admin/firestore");
const {FOUNDER_RIDER_UID} = require("./founder-rider-access");

const ACCOUNT_TYPE = "demo_account";
const PURPOSE = "google_play_review";
const DEFAULT_EXPIRY_HOURS = 168;
const MAX_EXPIRY_HOURS = 720;

function text(value, max) {
  return `${value || ""}`.trim().slice(0, max);
}

function requireFounder(context) {
  if (!context.auth || context.auth.uid !== FOUNDER_RIDER_UID) {
    throw new functions.https.HttpsError("permission-denied", "Founder authority is required.");
  }
}

function reviewerEmail(value) {
  const email = text(value, 320).toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    throw new functions.https.HttpsError("invalid-argument", "A valid reviewer email is required.");
  }
  return email;
}

function reviewerPassword(value) {
  const password = `${value || ""}`;
  if (password.length < 12) {
    throw new functions.https.HttpsError("invalid-argument", "A strong reviewer password is required.");
  }
  return password;
}

function expiry(value) {
  const hours = Number(value || DEFAULT_EXPIRY_HOURS);
  if (!Number.isFinite(hours) || hours <= 0 || hours > MAX_EXPIRY_HOURS) {
    throw new functions.https.HttpsError("invalid-argument", "Reviewer expiry is outside the supported range.");
  }
  return Timestamp.fromMillis(Date.now() + hours * 60 * 60 * 1000);
}

function provisionGooglePlayReviewer() {
  return functions.https.onCall({enforceAppCheck: true}, async (data, context) => {
    requireFounder(context);
    const email = reviewerEmail(data && data.email);
    const password = reviewerPassword(data && data.password);
    const displayName = text(data && data.displayName, 120) || "Google Play Reviewer";
    const expiresAt = expiry(data && data.expiryHours);
    let user;
    try {
      user = await getAuth().createUser({email, password, displayName, emailVerified: false});
      const db = getFirestore();
      const now = FieldValue.serverTimestamp();
      const authorityRef = db.collection("founderTestAccounts").doc(user.uid);
      const auditRef = db.collection("founderReviewAudit").doc();
      await db.runTransaction(async (transaction) => {
        transaction.set(authorityRef, {
          reviewerUid: user.uid,
          targetUid: user.uid,
          accountType: ACCOUNT_TYPE,
          purpose: PURPOSE,
          enabled: true,
          active: true,
          createdBy: context.auth.uid,
          createdAt: now,
          expiresAt,
          revokedAt: null,
        });
        transaction.set(db.collection("riders").doc(user.uid), {
          uid: user.uid,
          email,
          name: displayName,
          accountType: ACCOUNT_TYPE,
          purpose: PURPOSE,
          reviewOnly: true,
          approvalStatus: "approved",
          verificationStatus: "approved",
          onboardingStatus: "approved",
          riderStatus: "active",
          createdAt: now,
          updatedAt: now,
        });
        transaction.set(auditRef, {
          action: "provision_google_play_reviewer",
          actorUid: context.auth.uid,
          reviewerUid: user.uid,
          purpose: PURPOSE,
          accountType: ACCOUNT_TYPE,
          createdAt: now,
          expiresAt,
          passwordStored: false,
          immutable: true,
        });
      });
      return {ok: true, reviewerUid: user.uid, accountType: ACCOUNT_TYPE, purpose: PURPOSE, expiresAt: expiresAt.toMillis(), auditId: auditRef.id};
    } catch (error) {
      if (user) await getAuth().deleteUser(user.uid).catch(() => {});
      if (error instanceof functions.https.HttpsError) throw error;
      if (error && error.code === "auth/email-already-exists") {
        throw new functions.https.HttpsError("already-exists", "That reviewer email is already in use.");
      }
      throw new functions.https.HttpsError("internal", "Reviewer provisioning failed safely.");
    }
  });
}

module.exports = {provisionGooglePlayReviewer, _private: {ACCOUNT_TYPE, PURPOSE, MAX_EXPIRY_HOURS}};
