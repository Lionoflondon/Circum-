"use strict";
const functions = require("firebase-functions/v1");
const {getAuth} = require("firebase-admin/auth");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");

const FOUNDER_RIDER_UID = "T2eV6PQucdUKmwSipEn2NAn4N9z1";
function isAdmin(context) {
  const token = context.auth && context.auth.token || {};
  const roles = Array.isArray(token.roles) ? token.roles : [];
  return token.admin === true || token.super_admin === true || [token.role, token.adminRole, ...roles].some((v) => ["super_admin", "operations_admin"].includes(`${v || ""}`.toLowerCase()));
}
function assertFounderTarget(uid) {
  if (uid !== FOUNDER_RIDER_UID) throw new functions.https.HttpsError("permission-denied", "Founder Rider access is restricted to the authorised UID.");
}
function setFounderRiderAccess() {
  return functions.https.onCall(async (data, context) => {
    if (!context.auth || !isAdmin(context)) throw new functions.https.HttpsError("permission-denied", "Admin access is required.");
    const uid = `${data && data.uid || ""}`;
    assertFounderTarget(uid);
    const enabled = data && data.enabled === true;
    const user = await getAuth().getUser(uid);
    const claims = {...(user.customClaims || {})};
    if (enabled) claims.founderRider = true; else delete claims.founderRider;
    await getAuth().setCustomUserClaims(uid, claims);
    const db = getFirestore();
    const now = FieldValue.serverTimestamp();
    const founderPatch = enabled ? {
      founderRider: true,
      founderRecognition: "founder",
      founderRecognitionUpdatedAt: now,
      recognitions: {
        founder: {
          awarded: true,
          title: "Founder",
          source: "canonical_founder_identity",
          awardedAt: now,
          awardedBy: context.auth.uid,
        },
      },
    } : {
      founderRider: false,
      founderRecognition: FieldValue.delete(),
      founderRecognitionUpdatedAt: now,
      recognitions: {
        founder: {
          awarded: false,
          revokedAt: now,
          revokedBy: context.auth.uid,
        },
      },
    };
    await Promise.all([
      db.collection("riderProfiles").doc(uid).set(founderPatch, {merge: true}),
      db.collection("riders").doc(uid).set(founderPatch, {merge: true}),
      db.collection("founderRiderAccessAudit").add({uid, enabled, actorUid: context.auth.uid, reason: `${data && data.reason || "Founder Rider access update"}`, createdAt: now, mechanism: "firebase_auth_custom_claim_and_profile_projection"}),
    ]);
    return {success: true, uid, enabled};
  });
}
module.exports = {FOUNDER_RIDER_UID, assertFounderTarget, setFounderRiderAccess};
