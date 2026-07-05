/* eslint-disable max-len, require-jsdoc */
const functions = require("firebase-functions/v1");
const {searchFreeUkAddresses} = require("./free-address-core");

exports.searchFreeUkAddresses = functions.https.onCall(async (data) => {
  const query = `${data && data.query || ""}`.trim();
  if (query.length < 3) {
    return {status: "ZERO_RESULTS", results: []};
  }
  try {
    return await searchFreeUkAddresses({query});
  } catch (error) {
    console.error("Free UK address search failed", error);
    throw new functions.https.HttpsError(
        "unavailable",
        "Address search is unavailable. Enter the address manually or try again.",
    );
  }
});
