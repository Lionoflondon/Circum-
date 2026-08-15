/* eslint-disable max-len, require-jsdoc */
const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const {
  resolveUkAddressPlace,
  searchFreeUkAddresses,
} = require("./free-address-core");
const {checkAndConsumeRateLimit} = require("./rate-limit-core");

function googlePlacesApiKey() {
  return `${process.env.GOOGLE_PLACES_API_KEY ||
    process.env.CIRCUM_GOOGLE_PLACES_API_KEY ||
    ""}`.trim();
}

function requireAuth(context) {
  if (!context || !context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Authentication required.");
  }
}

function validateSessionToken(value) {
  const sessionToken = `${value || ""}`.trim();
  if (sessionToken.length > 256 || (sessionToken && !/^[A-Za-z0-9_-]+$/.test(sessionToken))) {
    throw new functions.https.HttpsError("invalid-argument", "Invalid session token.");
  }
  return sessionToken;
}

async function consumeAddressLimit(context, db) {
  const rateLimit = await checkAndConsumeRateLimit({
    db,
    key: `address_api_${context.auth.uid}`,
    max: 20,
    windowSeconds: 60,
  });
  if (!rateLimit.allowed) {
    throw new functions.https.HttpsError(
        "resource-exhausted",
        "Too many address requests - please slow down.",
    );
  }
}

async function searchFreeUkAddressesHandler(data, context, {db, searchImpl = searchFreeUkAddresses} = {}) {
  requireAuth(context);
  const query = `${data && data.query || ""}`.replace(/\s+/g, " ").trim();
  if (!query) {
    throw new functions.https.HttpsError("invalid-argument", "A search query is required.");
  }
  if (query.length > 160) {
    throw new functions.https.HttpsError("invalid-argument", "Address search is too long.");
  }
  const sessionToken = validateSessionToken(data && data.sessionToken);
  if (query.length < 3) return {status: "ZERO_RESULTS", results: []};
  await consumeAddressLimit(context, db || admin.firestore());
  try {
    return await searchImpl({
      query,
      sessionToken,
      googlePlacesApiKey: googlePlacesApiKey(),
    });
  } catch (error) {
    console.error("UK address search failed", error);
    throw new functions.https.HttpsError(
        "unavailable",
        "Address search is unavailable. Enter the address manually or try again.",
    );
  }
}

async function resolveUkAddressPlaceHandler(data, context, {db, resolveImpl = resolveUkAddressPlace} = {}) {
  requireAuth(context);
  const placeId = `${data && data.placeId || ""}`.trim();
  if (!placeId || placeId.length > 512 || !/^[A-Za-z0-9._:-]+$/.test(placeId)) {
    throw new functions.https.HttpsError("invalid-argument", "A valid selected address is required.");
  }
  const sessionToken = validateSessionToken(data && data.sessionToken);
  await consumeAddressLimit(context, db || admin.firestore());
  try {
    return await resolveImpl({
      placeId,
      sourceInput: `${data && data.sourceInput || ""}`.replace(/\s+/g, " ").trim(),
      sessionToken,
      googlePlacesApiKey: googlePlacesApiKey(),
    });
  } catch (error) {
    console.error("UK address details lookup failed", {placeId, error});
    throw new functions.https.HttpsError(
        "unavailable",
        "Address details are unavailable. Enter the address manually or try again.",
    );
  }
}

exports.searchFreeUkAddresses = functions.runWith({enforceAppCheck: true}).https.onCall((data, context) =>
  searchFreeUkAddressesHandler(data, context));
exports.resolveUkAddressPlace = functions.runWith({enforceAppCheck: true}).https.onCall((data, context) =>
  resolveUkAddressPlaceHandler(data, context));
exports._searchFreeUkAddressesHandler = searchFreeUkAddressesHandler;
exports._resolveUkAddressPlaceHandler = resolveUkAddressPlaceHandler;
