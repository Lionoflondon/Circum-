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
  try {
    const response = await fetchImpl("https://routes.googleapis.com/directions/v2:computeRoutes", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": apiKey,
        "X-Goog-FieldMask": "routes.distanceMeters",
      },
      body: JSON.stringify({
        origin: {address: pharmacyAddress},
        destination: {address: deliveryAddress},
        travelMode: "DRIVE",
        routingPreference: "TRAFFIC_UNAWARE",
      }),
      signal: AbortSignal.timeout(10000),
    });
    if (!response.ok) throw new Error("route_http");
    const body = await response.json();
    const route = body.routes && body.routes[0];
    const metres = Number(route && route.distanceMeters);
    if (!Number.isFinite(metres) || metres <= 0) {
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
