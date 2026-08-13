/* eslint-disable max-len, require-jsdoc */
const functions = require("firebase-functions/v1");
const {
  resolveUkAddressPlace,
  searchFreeUkAddresses,
} = require("./free-address-core");

function googlePlacesApiKey() {
  const config = functions.config() || {};
  return `${process.env.GOOGLE_PLACES_API_KEY ||
    process.env.CIRCUM_GOOGLE_PLACES_API_KEY ||
    config.google && config.google.places_api_key ||
    ""}`.trim();
}

function requireFirstParty(context) {
  if (!context || !context.auth || !context.auth.uid) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in to search for an address.");
  }
  if (!context.app) {
    throw new functions.https.HttpsError("failed-precondition", "Security verification is required.");
  }
}

exports.searchFreeUkAddresses = functions.https.onCall(async (data, context) => {
  requireFirstParty(context);
  const query = `${data && data.query || ""}`.trim();
  const sessionToken = `${data && data.sessionToken || ""}`.trim();
  if (query.length < 3) {
    return {status: "ZERO_RESULTS", results: []};
  }
  try {
    return await searchFreeUkAddresses({
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
});

exports.resolveUkAddressPlace = functions.https.onCall(async (data, context) => {
  requireFirstParty(context);
  const placeId = `${data && data.placeId || ""}`.trim();
  const sessionToken = `${data && data.sessionToken || ""}`.trim();
  if (!placeId) {
    throw new functions.https.HttpsError("invalid-argument", "A selected address is required.");
  }
  try {
    return await resolveUkAddressPlace({
      placeId,
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
});
