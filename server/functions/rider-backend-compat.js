/* eslint-disable max-len, require-jsdoc */
"use strict";
const functions = require("firebase-functions/v1");
const {riderCallable} = require("./rider-app-check");
const OWNERS = Object.freeze({
  createStripeConnectAccountForRider: "circum-rider-connect-accounts",
  createStripeOnboardingLink: "circum-rider-connect-accounts",
  refreshStripeOnboardingLink: "circum-rider-connect-accounts",
  syncStripeConnectStatus: "circum-rider-connect-accounts",
  createStripeAccountManagementLink: "circum-rider-connect-accounts",
  riderPayoutReadiness: "circum-rider-payouts",
  createRiderTransferOrPayout: "circum-rider-payouts",
  requestRiderWithdrawal: "circum-rider-payouts",
  cancelRiderWithdrawal: "circum-rider-payouts",
  adminReviewRiderWithdrawal: "circum-rider-payouts",
  completeDelivery: "circum-rider-delivery-authority",
  updateDeliveryTrackingStatus: "circum-rider-delivery-authority",
});
const ERROR_CODES = new Set(["invalid-argument", "unauthenticated", "permission-denied", "not-found", "already-exists", "failed-precondition", "resource-exhausted", "unavailable", "deadline-exceeded", "internal", "aborted", "out-of-range", "unimplemented", "data-loss", "cancelled", "unknown"]);
function createCompat(operation, {fetchImpl = fetch} = {}) {
  const owner = OWNERS[operation];
  if (!owner) throw new TypeError("Unsupported Rider compatibility operation");
  return riderCallable(async (data, context) => {
    const headers = context.rawRequest?.headers || {};
    if (!context.auth || !/^Bearer \S+$/.test(headers.authorization || "")) throw new functions.https.HttpsError("unauthenticated", "Sign in to continue.");
    if (!context.app || !headers["x-firebase-appcheck"]) throw new functions.https.HttpsError("failed-precondition", "Rider security verification is required.");
    let body;
    try {
      // One dispatch only. A timeout never starts another financial attempt.
      const response = await fetchImpl(`https://${owner}-j2b7cicfwq-uc.a.run.app/${operation}`, {
        method: "POST", headers: {"content-type": "application/json", authorization: headers.authorization, "x-firebase-appcheck": headers["x-firebase-appcheck"]},
        body: JSON.stringify({data}), signal: AbortSignal.timeout(45000), redirect: "error",
      });
      body = await response.json();
      if (!response.ok && !body.error) throw new Error("owner_unavailable");
    } catch (_error) {
      throw new functions.https.HttpsError("unavailable", "Rider backend confirmation is unavailable. Retry the same request identity.");
    }
    if (body.error) {
      const code = String(body.error.status || "internal").toLowerCase().replace(/_/g, "-");
      throw new functions.https.HttpsError(ERROR_CODES.has(code) ? code : "internal", body.error.message || "Rider backend request failed.", body.error.details);
    }
    if (!Object.prototype.hasOwnProperty.call(body, "result")) throw new functions.https.HttpsError("internal", "Rider backend returned an invalid confirmation.");
    return body.result;
  });
}
module.exports = {createCompat, OWNERS};
