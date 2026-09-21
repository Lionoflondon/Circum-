"use strict";

const functions = require("firebase-functions/v1");

const SERVICE_URL = "https://circum-account-bootstrap-j2b7cicfwq-uc.a.run.app";
const OPERATIONS = Object.freeze({
  ensureSenderAccount: {appCheckRequired: false},
  updateRiderProfile: {appCheckRequired: true},
});
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

function appCheckHeader(context) {
  const request = context && context.rawRequest;
  const value = request && (request.get && request.get("x-firebase-appcheck") ||
    request.headers && (request.headers["x-firebase-appcheck"] || request.headers["X-Firebase-AppCheck"]));
  return typeof value === "string" ? value.trim() : "";
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

function createAccountBootstrapCompat(name, options = {}) {
  const operation = OPERATIONS[name];
  if (!operation) throw new Error(`Unsupported account bootstrap operation: ${name}`);
  const fetchImpl = options.fetchImpl || fetch;
  const endpoint = options.endpoint || `${SERVICE_URL}/${name}`;
  return async (data, context) => {
    if (!context || !context.auth || !context.auth.uid) {
      throw new functions.https.HttpsError("unauthenticated", "Sign in to continue.");
    }
    const authorization = authorizationHeader(context);
    if (!authorization) {
      throw new functions.https.HttpsError("unauthenticated", "Sign in to continue.");
    }
    const appCheckToken = appCheckHeader(context);
    if (operation.appCheckRequired && (!context.app || !appCheckToken)) {
      throw new functions.https.HttpsError("failed-precondition", "Circum security verification is required.");
    }

    let response;
    const headers = {
      authorization,
      "content-type": "application/json",
    };
    if (operation.appCheckRequired) headers["x-firebase-appcheck"] = appCheckToken;
    try {
      response = await fetchImpl(endpoint, {
        method: "POST",
        headers,
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

const runtimeOptions = {
  memory: "256MB",
  timeoutSeconds: 60,
  maxInstances: 10,
};
const ensureSenderAccount = functions.runWith(runtimeOptions).https.onCall(
    createAccountBootstrapCompat("ensureSenderAccount"),
);
const updateRiderProfile = functions.runWith(runtimeOptions).https.onCall(
    createAccountBootstrapCompat("updateRiderProfile"),
);

module.exports = {createAccountBootstrapCompat, ensureSenderAccount, updateRiderProfile};
