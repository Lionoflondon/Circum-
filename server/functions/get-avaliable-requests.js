/* eslint-disable max-len */
const functions = require("firebase-functions");
const {getFirestore} = require("firebase-admin/firestore");

const getNearbyRequests = functions.https.onCall(async (data, context) => {
  try {
    const toRadians = (degrees) => {
      return degrees * (Math.PI / 180);
    };

    // Check if the user is authenticated
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated",
          "User must be authenticated to call this function.");
    }

    const riderId = context.auth.uid;

    // Get rider's current position
    const riderDoc = await getFirestore().collection("riders").doc(riderId).get();
    if (!riderDoc.exists) {
      throw new functions.https.HttpsError("not-found", "Rider not found");
    }

    const riderData = riderDoc.data();
    if (!riderData.position.geopoint.latitude || !riderData.position.geopoint.longitude) {
      throw new functions.https.HttpsError("failed-precondition", "Rider position not available");
    }

    const riderPosition = {
      latitude: riderData.position.geopoint.latitude,
      longitude: riderData.position.geopoint.longitude,
    };

    // Get all available delivery requests
    const requestsSnapshot = await getFirestore().collection("deliveryRequests")
        .where("status", "==", "requested") // Assuming 'pending' status for available requests
        .get();

    // Calculate distances from rider to each request
    const requestsWithDistances = await Promise.all(
        requestsSnapshot.docs
            .filter((doc) => {
              const requestData = doc.data();
              return requestData.pickupPosition.geopoint.latitude &&
                     requestData.pickupPosition.geopoint.longitude;
            })
            .map(async (doc) => {
              try {
                const requestData = doc.data();
                const pickupLocation = requestData.pickupPosition.geopoint;

                // Haversine formula for distance calculation
                const R = 6371; // Earth's radius in kilometers
                const dLat = toRadians(pickupLocation.latitude - riderPosition.latitude);
                const dLon = toRadians(pickupLocation.longitude - riderPosition.longitude);

                const a =
                  Math.sin(dLat/2) * Math.sin(dLat/2) +
                  Math.cos(toRadians(riderPosition.latitude)) *
                  Math.cos(toRadians(pickupLocation.latitude)) *
                  Math.sin(dLon/2) * Math.sin(dLon/2);

                const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
                const distance = R * c; // Distance in kilometers

                return {
                  id: doc.id,
                  ...requestData,
                  distanceFromRider: distance,
                };
              } catch (error) {
                console.error("Error processing request:", error);
                return null;
              }
            }),
    );

    // Filter out null values and get 5 closest requests
    const nearestRequests = requestsWithDistances
        .filter((request) => request !== null)
        .sort((a, b) => a.distanceFromRider - b.distanceFromRider)
        .slice(0, 5);

    return {
      riderId: riderId,
      riderPosition: riderPosition,
      nearestRequests: nearestRequests,
    };
  } catch (error) {
    console.error("Error in getNearbyRequests:", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
});

module.exports = getNearbyRequests;
