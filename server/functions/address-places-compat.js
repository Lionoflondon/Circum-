/* eslint-disable max-len, require-jsdoc */
"use strict";

const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");
const {createHandlers, createRateLimiter} = require("./cloud-run-address-places");

const placesKey = defineSecret("BACKEND_GOOGLE_PLACES_API_KEY");
const allowRequest = createRateLimiter();

function callableOptions() {
  return {
    region: "us-central1",
    secrets: [placesKey],
    enforceAppCheck: true,
    timeoutSeconds: 15,
    memory: "256MiB",
    maxInstances: 5,
    concurrency: 20,
  };
}

function translate(error) {
  const code = String(error && error.code || "internal").replace(/^functions\//, "");
  const supported = new Set([
    "invalid-argument",
    "unauthenticated",
    "permission-denied",
    "failed-precondition",
    "resource-exhausted",
    "unavailable",
  ]);
  return new HttpsError(supported.has(code) ? code : "internal", code === "internal" ? "Address request failed." : error.message);
}

function legacyCallable(operation) {
  return onCall(callableOptions(), async (request) => {
    if (!request.auth || !request.auth.uid) {
      throw new HttpsError("unauthenticated", "Sign in to continue.");
    }
    if (!allowRequest(request.auth.uid)) {
      throw new HttpsError("resource-exhausted", "Too many address requests. Try again shortly.");
    }
    try {
      const handlers = createHandlers({googlePlacesApiKey: placesKey.value()});
      return await handlers[operation](request.data, {auth: request.auth});
    } catch (error) {
      throw translate(error);
    }
  });
}

exports.searchFreeUkAddresses = legacyCallable("searchFreeUkAddresses");
exports.resolveUkAddressPlace = legacyCallable("resolveUkAddressPlace");

module.exports.callableOptions = callableOptions;
module.exports.legacyCallable = legacyCallable;
