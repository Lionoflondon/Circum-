/* eslint-disable max-len, require-jsdoc */
"use strict";

const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");

const FOUNDER_UID = "T2eV6PQucdUKmwSipEn2NAn4N9z1";
const FOUNDER_EMAIL = "ayojason600@gmail.com";

const TEST_ACCOUNT_TYPES = new Set(["internal_tester", "qa_account", "demo_account"]);
const TEST_WAIVERS = new Set([
  "rider_onboarding",
  "vehicle_registration",
  "vehicle_information",
  "document_approval",
  "dispatch_eligibility",
  "approval_status",
  "verification_status",
  "admin_approval",
  "account_status",
  "profile_photo",
  "identity",
  "insurance",
  "right_to_work",
]);

function text(value, max = 500) {
  return `${value || ""}`.trim().slice(0, max);
}

function lower(value, max = 500) {
  return text(value, max).toLowerCase();
}

function isFounderContext(context = {}) {
  const auth = context.auth || {};
  const token = auth.token || {};
  return auth.uid === FOUNDER_UID &&
    lower(token.email) === FOUNDER_EMAIL;
}

function assertFounder(context) {
  if (!context || !context.auth || !context.auth.uid) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in first.");
  }
  if (!isFounderContext(context)) {
    throw new functions.https.HttpsError(
        "permission-denied",
        "Founder authority is restricted to the authorised account.",
    );
  }
  return {
    uid: FOUNDER_UID,
    email: FOUNDER_EMAIL,
  };
}

function cleanTestType(value) {
  const type = lower(value).replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "");
  if (!TEST_ACCOUNT_TYPES.has(type)) {
    throw new functions.https.HttpsError("invalid-argument", "A supported test account type is required.");
  }
  return type;
}

function cleanWaivers(values = []) {
  if (!Array.isArray(values)) return [];
  return [...new Set(values.map((value) => lower(value).replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "")).filter((value) => TEST_WAIVERS.has(value)))];
}

function founderDesignateTestAccount() {
  return functions.https.onCall(async (data, context) => {
    const founder = assertFounder(context);
    const db = getFirestore();
    const targetUid = text(data && data.targetUid, 128);
    const accountType = cleanTestType(data && data.accountType);
    const reason = text(data && data.reason, 1000);
    const waivers = cleanWaivers(data && data.waivers);
    if (!targetUid) {
      throw new functions.https.HttpsError("invalid-argument", "A target account is required.");
    }
    if (!reason || reason.length < 12) {
      throw new functions.https.HttpsError("invalid-argument", "A detailed Founder test designation reason is required.");
    }
    const ref = db.collection("founderTestAccounts").doc(targetUid);
    const auditRef = db.collection("founderAuthorityAudit").doc();
    const result = await db.runTransaction(async (transaction) => {
      const beforeSnap = await transaction.get(ref);
      const before = beforeSnap.exists ? beforeSnap.data() : {};
      const patch = {
        targetUid,
        accountType,
        waivers,
        active: data && data.active === false ? false : true,
        reason,
        founderUid: founder.uid,
        founderEmail: founder.email,
        updatedAt: FieldValue.serverTimestamp(),
      };
      transaction.set(ref, patch, {merge: true});
      const audit = {
        founderUid: founder.uid,
        founderEmail: founder.email,
        targetUid,
        action: "founder_designate_test_account",
        previousValues: before,
        newValues: patch,
        reason,
        createdAt: FieldValue.serverTimestamp(),
        immutable: true,
      };
      transaction.set(auditRef, audit);
      return {auditId: auditRef.id, before, after: patch};
    });
    return {
      ok: true,
      targetUid,
      auditId: result.auditId,
      accountType,
      waivers,
      active: result.after.active,
    };
  });
}

async function loadFounderTestAccount(db, uid) {
  const targetUid = text(uid, 128);
  if (!targetUid) return null;
  const snap = await db.collection("founderTestAccounts").doc(targetUid).get();
  if (!snap.exists) return null;
  const data = snap.data() || {};
  if (data.active !== true) return null;
  const accountType = cleanTestType(data.accountType);
  const waivers = cleanWaivers(data.waivers);
  return {
    active: true,
    targetUid,
    accountType,
    waivers,
  };
}

module.exports = {
  FOUNDER_UID,
  FOUNDER_EMAIL,
  assertFounder,
  isFounderContext,
  founderDesignateTestAccount,
  loadFounderTestAccount,
};
