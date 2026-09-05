/* eslint-disable max-len, require-jsdoc */
const functions = require("firebase-functions/v1");
const {defineSecret} = require("firebase-functions/params");
const healthDirectionsKey = defineSecret("GOOGLE_MAPS_DIRECTIONS_API_KEY");
async function healthRouteDistance({
  pharmacyAddress,
  deliveryAddress,
  apiKey = healthDirectionsKey.value(),
  fetchImpl = fetch,
}) {
  if (
    !apiKey ||
    !String(pharmacyAddress || "").trim() ||
    !String(deliveryAddress || "").trim()
  ) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Complete the pharmacy and delivery addresses before pricing.",
    );
  }
  const url = new URL("https://maps.googleapis.com/maps/api/directions/json");
  url.searchParams.set("origin", pharmacyAddress);
  url.searchParams.set("destination", deliveryAddress);
  url.searchParams.set("mode", "driving");
  url.searchParams.set("key", apiKey);
  try {
    const response = await fetchImpl(url, {
      signal: AbortSignal.timeout(10000),
    });
    if (!response.ok) throw new Error("route_http");
    const body = await response.json();
    const leg =
      body.routes &&
      body.routes[0] &&
      body.routes[0].legs &&
      body.routes[0].legs[0];
    const metres = Number(leg && leg.distance && leg.distance.value);
    if (body.status !== "OK" || !Number.isFinite(metres) || metres <= 0) {
      throw new Error("route_missing");
    }
    return metres / 1609.344;
  } catch (_) {
    throw new functions.https.HttpsError(
      "unavailable",
      "Health+ route could not be verified. Check the addresses and try again.",
    );
  }
}
module.exports = {healthRouteDistance, healthDirectionsKey};
