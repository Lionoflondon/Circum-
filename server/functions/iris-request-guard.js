/* eslint-disable require-jsdoc */
"use strict";

const crypto = require("crypto");
const functions = require("firebase-functions/v1");
const {FieldValue} = require("firebase-admin/firestore");

const WINDOW_MS = 10 * 60 * 1000;
const LIMITS = Object.freeze({analyse_iris: 120, analyse_iris_photo: 24, report_load_discrepancy: 20});

function safeId(value) {
  return crypto.createHash("sha256").update(`${value || ""}`).digest("hex").slice(0, 32);
}

async function enforceIrisRequestLimit({db, uid, action, now = Date.now()}) {
  const limit = LIMITS[action];
  if (!uid || !limit) throw new Error("A supported authenticated IRIS action is required.");
  const bucket = Math.floor(now / WINDOW_MS);
  const ref = db.collection("rateLimits").doc(`iris_${safeId(uid)}_${action}_${bucket}`);
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    const count = snapshot.exists ? Number(snapshot.data().count || 0) : 0;
    if (count >= limit) {
      throw new functions.https.HttpsError(
          "resource-exhausted",
          "IRIS is receiving too many requests. Please wait a few minutes and try again.",
      );
    }
    transaction.set(ref, {
      action,
      count: count + 1,
      expiresAt: new Date((bucket + 2) * WINDOW_MS),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  });
}

module.exports = {LIMITS, WINDOW_MS, enforceIrisRequestLimit};
