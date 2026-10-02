/* eslint-disable max-len, require-jsdoc */
"use strict";

const {onCall, HttpsError} = require("firebase-functions/v2/https");
const ENDPOINTS = Object.freeze({
  verifyRiderAccountAccess: "https://circum-account-bootstrap-j2b7cicfwq-uc.a.run.app/verifyRiderAccountAccess",
  createBusinessGiftOrder: "https://circum-business-invoice-payments-j2b7cicfwq-uc.a.run.app/createBusinessGiftOrder",
});
const CODES = new Set(["cancelled", "unknown", "invalid-argument", "deadline-exceeded", "not-found", "already-exists", "permission-denied", "resource-exhausted", "failed-precondition", "aborted", "out-of-range", "unimplemented", "internal", "unavailable", "data-loss", "unauthenticated"]);

function createProxy(name, fetchImpl = fetch) {
  const endpoint = ENDPOINTS[name];
  if (!endpoint) throw new Error("Unsupported compatibility operation.");
  return async (request) => {
    if (!request.auth || !request.auth.uid) throw new HttpsError("unauthenticated", "Sign in to continue.");
    if (!request.app) throw new HttpsError("failed-precondition", "Security verification is required.");
    const headers = request.rawRequest && request.rawRequest.headers || {};
    const authorization = headers.authorization;
    const appCheck = headers["x-firebase-appcheck"];
    if (typeof authorization !== "string" || !/^Bearer\s+\S+$/.test(authorization)) throw new HttpsError("unauthenticated", "Sign in to continue.");
    if (typeof appCheck !== "string" || !appCheck.trim()) throw new HttpsError("failed-precondition", "Security verification is required.");
    let response;
    try {
      response = await fetchImpl(endpoint, {
        method: "POST",
        headers: {authorization, "x-firebase-appcheck": appCheck, "content-type": "application/json"},
        body: JSON.stringify({data: request.data || {}}),
        signal: AbortSignal.timeout(55000),
      });
    } catch {
      // Never retry a potentially mutating payment/order request at this edge.
      throw new HttpsError("unavailable", "The service is temporarily unavailable.");
    }
    let payload;
    try {
      payload = await response.json();
    } catch {
      throw new HttpsError("internal", "The service returned an invalid response.");
    }
    if (!response.ok || payload && payload.error) {
      const code = String(payload && payload.error && payload.error.status || "internal").toLowerCase().replaceAll("_", "-");
      throw new HttpsError(CODES.has(code) ? code : "internal", "The request could not be completed.", payload && payload.error && payload.error.details);
    }
    if (!payload || !Object.prototype.hasOwnProperty.call(payload, "result")) throw new HttpsError("internal", "The service returned an invalid response.");
    return payload.result;
  };
}

const options = {region: "us-central1", enforceAppCheck: true, timeoutSeconds: 60, memory: "256MiB", maxInstances: 1};
exports.verifyRiderAccountAccess = onCall(options, createProxy("verifyRiderAccountAccess"));
exports.createBusinessGiftOrder = onCall(options, createProxy("createBusinessGiftOrder"));
exports.createProxy = createProxy;
exports.ENDPOINTS = ENDPOINTS;
