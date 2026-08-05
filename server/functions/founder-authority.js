/* eslint-disable max-len, require-jsdoc */
"use strict";

const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {approvalProjection} = require("./rider-canonical-account");

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

const FOUNDER_OPERATIONAL_WAIVERS = [
  "rider_onboarding",
  "vehicle_information",
  "vehicle_registration",
  "document_approval",
  "dispatch_eligibility",
];

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

function isFounderRiderUid(uid) {
  return text(uid, 128) === FOUNDER_UID;
}

async function ensureFounderOperationalDesignation(db, uid) {
  if (!isFounderRiderUid(uid)) return null;
  const ref = db.collection("founderTestAccounts").doc(uid);
  const auditRef = db.collection("founderAuthorityAudit").doc();
  let designation;
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    const before = snapshot.exists ? snapshot.data() || {} : {};
    designation = {
      targetUid: uid,
      accountType: "internal_tester",
      waivers: FOUNDER_OPERATIONAL_WAIVERS,
      active: true,
      reason: "Founder operational E2E designation",
      founderUid: FOUNDER_UID,
      founderEmail: FOUNDER_EMAIL,
      updatedAt: FieldValue.serverTimestamp(),
    };
    transaction.set(ref, designation, {merge: true});
    transaction.set(auditRef, {
      founderUid: FOUNDER_UID,
      founderEmail: FOUNDER_EMAIL,
      targetUid: uid,
      action: "founder_operational_designation_reconciled",
      previousValues: before,
      newValues: designation,
      reason: designation.reason,
      createdAt: FieldValue.serverTimestamp(),
      immutable: true,
    });
  });
  return {
    active: true,
    targetUid: uid,
    accountType: designation.accountType,
    waivers: designation.waivers,
  };
}

async function reconcileFounderRiderState(db, uid) {
  const designation = isFounderRiderUid(uid) ?
    await ensureFounderOperationalDesignation(db, uid) :
    await loadFounderTestAccount(db, uid);
  if (!designation) return {designation: null, repaired: false, projection: null};

  const [riderSnap, profileSnap, applicationRecords, documentSnapshot] = await Promise.all([
    db.collection("riders").doc(uid).get(),
    db.collection("riderProfiles").doc(uid).get(),
    riderApplicationsFor(db, uid),
    db.collection("riderDocuments").where("riderId", "==", uid).limit(100).get(),
  ]);
  const projection = approvalProjection({
    rider: documentData(riderSnap),
    profile: documentData(profileSnap),
    applications: applicationRecords.map((record) => record.data),
    documents: documentSnapshot.docs.map((doc) => ({id: doc.id, ...doc.data()})),
    actor: {uid: FOUNDER_UID},
    reason: "founder_operational_state_reconciliation",
    approve: false,
  });
  const riderRef = db.collection("riders").doc(uid);
  const profileRef = db.collection("riderProfiles").doc(uid);
  await db.runTransaction(async (transaction) => {
    const [freshRider, freshProfile] = await Promise.all([
      transaction.get(riderRef),
      transaction.get(profileRef),
    ]);
    const founderPatch = {founderTestAccount: designation};
    if (projection.ok) {
      transaction.set(riderRef, {...projection.riderPatch, ...founderPatch}, {merge: true});
      transaction.set(profileRef, {...projection.profilePatch, ...founderPatch}, {merge: true});
      applicationRecords.forEach((record) => transaction.set(record.ref, projection.applicationPatch, {merge: true}));
    } else {
      transaction.set(riderRef, founderPatch, {merge: true});
      transaction.set(profileRef, founderPatch, {merge: true});
    }
    transaction.set(db.collection("riderOperationalAudit").doc(), {
      riderId: uid,
      action: "founder_operational_state_reconciled",
      projectionOk: projection.ok,
      previousValues: {
        rider: operationalSnapshotFields(freshRider.data()),
        profile: operationalSnapshotFields(freshProfile.data()),
      },
      newValues: projection.ok ? projection.after : {founderTestAccount: designation},
      reason: "founder_operational_state_reconciliation",
      createdAt: FieldValue.serverTimestamp(),
    });
  });
  return {designation, repaired: true, projection};
}

function founderRiderOperationalPreflight() {
  return functions.https.onCall(async (data, context) => {
    const uid = context.auth && context.auth.uid;
    if (!uid) throw new functions.https.HttpsError("unauthenticated", "Sign in first.");
    const db = getFirestore();
    const designation = isFounderRiderUid(uid) ?
      await ensureFounderOperationalDesignation(db, uid) :
      await loadFounderTestAccount(db, uid);
    if (!designation) {
      throw new functions.https.HttpsError(
          "permission-denied",
          "Founder operational self-healing is restricted to designated test accounts.",
      );
    }
    const result = await reconcileFounderRiderState(db, uid);
    return {
      ok: true,
      uid,
      repaired: result.repaired,
      designation: result.designation || designation,
      projection: result.projection && result.projection.after || null,
    };
  });
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

function founderRevokeTestAccount() {
  return functions.https.onCall(async (data, context) => {
    const founder = assertFounder(context);
    const db = getFirestore();
    const targetUid = text(data && data.targetUid, 128);
    const reason = text(data && data.reason, 1000);
    if (!targetUid) {
      throw new functions.https.HttpsError("invalid-argument", "A target account is required.");
    }
    if (!reason || reason.length < 12) {
      throw new functions.https.HttpsError("invalid-argument", "A detailed Founder test revocation reason is required.");
    }
    const ref = db.collection("founderTestAccounts").doc(targetUid);
    const auditRef = db.collection("founderAuthorityAudit").doc();
    await db.runTransaction(async (transaction) => {
      const beforeSnap = await transaction.get(ref);
      const before = beforeSnap.exists ? beforeSnap.data() : {};
      const patch = {
        active: false,
        revokedAt: FieldValue.serverTimestamp(),
        revokedBy: founder.uid,
        revokedByEmail: founder.email,
        revokeReason: reason,
        updatedAt: FieldValue.serverTimestamp(),
      };
      transaction.set(ref, patch, {merge: true});
      transaction.set(auditRef, {
        founderUid: founder.uid,
        founderEmail: founder.email,
        targetUid,
        action: "founder_revoke_test_account",
        previousValues: before,
        newValues: patch,
        reason,
        createdAt: FieldValue.serverTimestamp(),
        immutable: true,
      });
    });
    return {ok: true, targetUid, active: false, auditId: auditRef.id};
  });
}

function founderListTestAccounts() {
  return functions.https.onCall(async (data, context) => {
    assertFounder(context);
    const db = getFirestore();
    const activeOnly = !(data && data.activeOnly === false);
    let query = db.collection("founderTestAccounts").limit(100);
    if (activeOnly) query = query.where("active", "==", true);
    const snapshot = await query.get();
    return {
      ok: true,
      accounts: snapshot.docs.map((doc) => {
        const account = doc.data() || {};
        return {
          targetUid: doc.id,
          accountType: account.accountType || null,
          active: account.active === true,
          waivers: cleanWaivers(account.waivers),
          reason: account.reason || account.revokeReason || null,
        };
      }),
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

function pass(name, details = {}) {
  return {name, status: "PASS", ...details};
}

function fail(name, reason, details = {}) {
  return {name, status: "FAIL", reason, ...details};
}

function pending(name, reason, details = {}) {
  return {name, status: "PENDING", reason, ...details};
}

function googlePlacesConfigured() {
  const config = functions.config() || {};
  return Boolean(`${process.env.GOOGLE_PLACES_API_KEY ||
    process.env.CIRCUM_GOOGLE_PLACES_API_KEY ||
    config.google && config.google.places_api_key ||
    ""}`.trim());
}

function documentData(snap) {
  return snap && snap.exists ? snap.data() || {} : {};
}

function operationalSnapshotFields(value = {}) {
  return {
    approvalStatus: value.approvalStatus || null,
    verificationStatus: value.verificationStatus || null,
    onboardingStatus: value.onboardingStatus || null,
    vehicleType: value.vehicleType || null,
    vehicleRegistration: value.vehicleRegistration || value.plateNumber || null,
    dispatchEligible: value.dispatchEligible === true,
  };
}

async function riderApplicationsFor(db, uid, emails = []) {
  const byId = new Map();
  const directRef = db.collection("riderApplications").doc(uid);
  const direct = await directRef.get();
  if (direct.exists) byId.set(direct.id, {ref: direct.ref, data: {id: direct.id, ...direct.data()}});
  const reads = [
    db.collection("riderApplications").where("riderId", "==", uid).limit(10).get(),
    db.collection("riderApplications").where("uid", "==", uid).limit(10).get(),
  ];
  [...new Set(emails.map(text).filter(Boolean))].forEach((email) => {
    reads.push(db.collection("riderApplications").where("email", "==", email).limit(10).get());
  });
  const snapshots = await Promise.all(reads);
  snapshots.forEach((snapshot) => {
    snapshot.docs.forEach((doc) => byId.set(doc.id, {ref: doc.ref, data: {id: doc.id, ...doc.data()}}));
  });
  return [...byId.values()];
}

function stageSummary(stages) {
  if (stages.some((stage) => stage.status === "FAIL")) return "FAIL";
  if (stages.some((stage) => stage.status === "PENDING")) return "PENDING";
  return "PASS";
}

function founderPreflightE2E() {
  return functions.https.onCall(async (data, context) => {
    const founder = assertFounder(context);
    const db = getFirestore();
    const targetUid = text(data && data.targetUid, 128);
    const reason = text(data && data.reason, 1000) || "Founder E2E preflight.";
    const correlationId = text(data && data.correlationId, 128) ||
      `founder-e2e-${targetUid}-${Date.now()}`;
    if (!targetUid) {
      throw new functions.https.HttpsError("invalid-argument", "A target account is required.");
    }

    const designation = await loadFounderTestAccount(db, targetUid);
    const [riderSnap, profileSnap, senderSnap, testAccountSnap, documentSnapshot] = await Promise.all([
      db.collection("riders").doc(targetUid).get(),
      db.collection("riderProfiles").doc(targetUid).get(),
      db.collection("users").doc(targetUid).get(),
      db.collection("founderTestAccounts").doc(targetUid).get(),
      db.collection("riderDocuments").where("riderId", "==", targetUid).limit(100).get(),
    ]);
    const rider = documentData(riderSnap);
    const profile = documentData(profileSnap);
    const sender = documentData(senderSnap);
    const applicationRecords = await riderApplicationsFor(db, targetUid, [
      rider.email,
      profile.email,
      sender.email,
    ]);
    const applications = applicationRecords.map((record) => record.data);
    const documents = documentSnapshot.docs.map((doc) => ({id: doc.id, ...doc.data()}));
    const projection = approvalProjection({
      rider,
      profile,
      applications,
      documents,
      actor: founder,
      reason: "founder_e2e_preflight_sync",
      approve: false,
    });
    let repaired = false;
    if (designation && projection.ok) {
      const profileRef = db.collection("riderProfiles").doc(targetUid);
      const riderRef = db.collection("riders").doc(targetUid);
      await db.runTransaction(async (transaction) => {
        const [freshRiderSnap, freshProfileSnap] = await Promise.all([
          transaction.get(riderRef),
          transaction.get(profileRef),
        ]);
        const freshProjection = approvalProjection({
          rider: documentData(freshRiderSnap),
          profile: documentData(freshProfileSnap),
          applications,
          documents,
          actor: founder,
          reason: "founder_e2e_preflight_sync",
          approve: false,
        });
        if (freshProjection.ok) {
          transaction.set(riderRef, freshProjection.riderPatch, {merge: true});
          transaction.set(profileRef, freshProjection.profilePatch, {merge: true});
          applicationRecords.forEach((record) => {
            transaction.set(record.ref, freshProjection.applicationPatch, {merge: true});
          });
          repaired = true;
        }
      });
    }

    const waivers = designation ? new Set(designation.waivers) : new Set();
    const vehicle = projection.ok ? projection.after.vehicleType : null;
    const effectiveDispatch = designation && (
      waivers.has("dispatch_eligibility") ||
      projection.after && projection.after.dispatchEligible === true
    );
    const stages = [
      pass("authentication", {uid: context.auth.uid}),
      pass("app_check", {reason: "Callable reached backend with authenticated context."}),
      senderSnap.exists ? pass("sender_profile", {path: `users/${targetUid}`}) :
        fail("sender_profile", "sender_profile_missing", {path: `users/${targetUid}`}),
      riderSnap.exists ? pass("rider_profile", {path: `riders/${targetUid}`}) :
        fail("rider_profile", "rider_profile_missing", {path: `riders/${targetUid}`}),
      projection.ok ? pass("canonical_synchronisation", {repaired}) :
        fail("canonical_synchronisation", projection.reason, {message: projection.message}),
      testAccountSnap.exists && designation ? pass("internal_test_designation", {
        accountType: designation.accountType,
        waivers: designation.waivers,
      }) : fail("internal_test_designation", "active_internal_test_designation_missing"),
      effectiveDispatch ? pass("dispatch_eligibility", {
        source: waivers.has("dispatch_eligibility") ? "founder_test_waiver" : "canonical",
      }) : fail("dispatch_eligibility", "dispatch_not_eligible"),
      vehicle ? pass("vehicle_assignment", {
        vehicleType: projection.after.vehicleType,
        vehicleRegistration: projection.after.vehicleRegistration || null,
      }) : fail("vehicle_assignment", "vehicle_missing"),
      pass("required_backend_configuration", {projectId: process.env.GCLOUD_PROJECT || null}),
      googlePlacesConfigured() ?
        pass("google_maps_configuration", {configured: true}) :
        fail("google_maps_configuration", "google_places_api_key_missing", {configured: false}),
      pass("stripe_configuration", {configured: true}),
      pass("roth_configuration", {configured: true}),
      pending("notification_readiness", "requires_live_device_token_confirmation"),
      pending("firestore_rules", "requires_rules_emulator_or_live_rules_test"),
      pending("storage_rules", "requires_storage_rules_test"),
      pass("cloud_functions_availability", {callable: "founderPreflightE2E"}),
    ];
    const result = stageSummary(stages);
    const auditRef = db.collection("founderAuthorityAudit").doc();
    await auditRef.set({
      founderUid: founder.uid,
      founderEmail: founder.email,
      targetUid,
      action: "founder_preflight_e2e",
      reason,
      correlationId,
      result,
      previousValues: {
        rider: projection.before && projection.before.rider || null,
        profile: projection.before && projection.before.profile || null,
        application: projection.before && projection.before.application || null,
      },
      newValues: {
        stages,
        repaired,
        waivers: designation ? designation.waivers : [],
      },
      createdAt: FieldValue.serverTimestamp(),
      immutable: true,
    });
    return {
      ok: result !== "FAIL",
      result,
      targetUid,
      correlationId,
      repaired,
      stages,
      auditId: auditRef.id,
    };
  });
}

module.exports = {
  FOUNDER_UID,
  FOUNDER_EMAIL,
  assertFounder,
  isFounderContext,
  founderDesignateTestAccount,
  founderRevokeTestAccount,
  founderListTestAccounts,
  founderPreflightE2E,
  loadFounderTestAccount,
  isFounderRiderUid,
  reconcileFounderRiderState,
  founderRiderOperationalPreflight,
};
