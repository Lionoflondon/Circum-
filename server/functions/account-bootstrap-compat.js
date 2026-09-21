"use strict";

const functions = require("firebase-functions/v1");

const ENDPOINT = "https://circum-account-bootstrap-j2b7cicfwq-uc.a.run.app/ensureSenderAccount";
const CALLABLE_CODES = new Set([
  "already-exists",
  "deadline-exceeded",
  "failed-precondition",
  "internal",
  "invalid-argument",
  "not-found",
  "permission-denied",
  "resource-exhausted",
  "unauthenticated",
  "unavailable",
]);

function authorizationHeader(context) {
  const request = context && context.rawRequest;
  const value = request && (request.get && request.get("authorization") ||
    request.headers && request.headers.authorization);
  return typeof value === "string" && /^Bearer\s+\S+$/.test(value) ? value : "";
}

function statusCode(status) {
  return ({
    400: "failed-precondition",
    401: "unauthenticated",
    403: "permission-denied",
    404: "not-found",
    409: "already-exists",
    429: "resource-exhausted",
    503: "unavailable",
  })[status] || (status >= 500 ? "internal" : "failed-precondition");
}

function createEnsureSenderAccountCompat(options = {}) {
  const fetchImpl = options.fetchImpl || fetch;
  const endpoint = options.endpoint || ENDPOINT;
  return async (data, context) => {
    if (!context || !context.auth || !context.auth.uid) {
      throw new functions.https.HttpsError("unauthenticated", "Sign in to continue.");
    }
    const authorization = authorizationHeader(context);
    if (!authorization) {
      throw new functions.https.HttpsError("unauthenticated", "Sign in to continue.");
    }

    let response;
    try {
      response = await fetchImpl(endpoint, {
        method: "POST",
        headers: {
          authorization,
          "content-type": "application/json",
        },
        body: JSON.stringify({data: data || {}}),
        signal: AbortSignal.timeout(55000),
      });
    } catch (_error) {
      throw new functions.https.HttpsError("unavailable", "Account service is temporarily unavailable.");
    }

    let payload;
    try {
      payload = await response.json();
    } catch (_error) {
      throw new functions.https.HttpsError("internal", "Account service returned an invalid response.");
    }
    if (!response.ok) {
      const upstreamCode = String(payload && payload.error && payload.error.status || "").toLowerCase().replaceAll("_", "-");
      const code = CALLABLE_CODES.has(upstreamCode) ? upstreamCode : statusCode(response.status);
      const message = payload && payload.error && typeof payload.error.message === "string" ?
        payload.error.message : "Account request failed.";
      throw new functions.https.HttpsError(code, message);
    }
    if (!payload || !Object.prototype.hasOwnProperty.call(payload, "result")) {
      throw new functions.https.HttpsError("internal", "Account service returned an invalid response.");
    }
    return payload.result;
  };
}

const ensureSenderAccount = functions.runWith({
  memory: "256MB",
  timeoutSeconds: 60,
  maxInstances: 10,
}).https.onCall(createEnsureSenderAccountCompat());

module.exports = {createEnsureSenderAccountCompat, ensureSenderAccount};
