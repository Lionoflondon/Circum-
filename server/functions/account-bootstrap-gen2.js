"use strict";

const {onCall, HttpsError} = require("firebase-functions/v2/https");
const senderAccount = require("./sender-account");
const riderAccount = require("./rider-account");

const REGION = "us-central1";
const BASE_OPTIONS = {
  region: REGION,
  timeoutSeconds: 60,
  memory: "256MiB",
  maxInstances: 10,
};

function normalizeCode(value) {
  const code = String(value || "internal").replace(/^functions\//, "");
  const supported = new Set([
    "cancelled",
    "unknown",
    "invalid-argument",
    "deadline-exceeded",
    "not-found",
    "already-exists",
    "permission-denied",
    "resource-exhausted",
    "failed-precondition",
    "aborted",
    "out-of-range",
    "unimplemented",
    "internal",
    "unavailable",
    "data-loss",
    "unauthenticated",
  ]);
  return supported.has(code) ? code : "internal";
}

function bridgeLegacyCallable(legacyCallable, {enforceAppCheck}) {
  return onCall({...BASE_OPTIONS, enforceAppCheck}, async (request) => {
    const context = {
      auth: request.auth,
      app: request.app,
      instanceIdToken: request.instanceIdToken,
      rawRequest: request.rawRequest,
    };
    try {
      return await legacyCallable.run(request.data || {}, context);
    } catch (error) {
      throw new HttpsError(
          normalizeCode(error && error.code),
          error && error.message ? error.message : "Account request failed.",
          error && error.details,
      );
    }
  });
}

// Sender clients historically called this endpoint before App Check was
// mandatory. Preserve that released-client contract while retaining auth and
// account-role enforcement in the canonical handler.
exports.ensureSenderAccount = bridgeLegacyCallable(
    senderAccount.ensureSenderAccount,
    {enforceAppCheck: false},
);

// Rider account recovery has always used the Rider App Check policy.
exports.verifyRiderAccountAccess = bridgeLegacyCallable(
    riderAccount.verifyRiderAccountAccess,
    {enforceAppCheck: true},
);
exports.updateRiderProfile = bridgeLegacyCallable(
    riderAccount.updateRiderProfile,
    {enforceAppCheck: true},
);

module.exports.bridgeLegacyCallable = bridgeLegacyCallable;
module.exports.normalizeCode = normalizeCode;

