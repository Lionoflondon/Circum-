/* eslint-disable max-len, require-jsdoc */
const functions = require("firebase-functions/v1");
const {
  resolveUkAddressPlace,
  searchFreeUkAddresses,
} = require("./free-address-core");

function googlePlacesApiKey() {
  return `${process.env.GOOGLE_PLACES_API_KEY ||
    process.env.CIRCUM_GOOGLE_PLACES_API_KEY ||
    ""}`.trim();
}

exports.searchFreeUkAddresses = functions.https.onCall(async (data) => {
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

exports.resolveUkAddressPlace = functions.https.onCall(async (data) => {
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

exports._googlePlacesApiKey = googlePlacesApiKey;
