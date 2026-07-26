/* eslint-disable max-len, require-jsdoc */
const functions = require("firebase-functions/v1");
const {getFirestore} = require("firebase-admin/firestore");
const {dispatchPriority, isDispatchable, riderCanViewDispatch, riderDispatchPriority, riderMatchesIris} = require("./iris-core");

const REQUEST_SCAN_LIMIT = 100;
const openStatuses = new Set(["requested", "pending", "broadcast", "broadcasted", "awaiting_rider", "finding_rider"]);
const text = (value) => `${value || ""}`.trim();

function riderLocality(rider = {}) {
  return text(rider.dispatchLocality || rider.locality || rider.city || rider.town || rider.area);
}

function deliveryLocality(delivery = {}) {
  return text(delivery.pickupLocality || delivery.collectionLocality || delivery.pickupCity || delivery.collectionCity);
}

function hasPickupGeo(delivery = {}) {
  return Boolean(delivery.pickupPosition &&
    delivery.pickupPosition.geopoint &&
    Number.isFinite(Number(delivery.pickupPosition.geopoint.latitude)) &&
    Number.isFinite(Number(delivery.pickupPosition.geopoint.longitude)));
}

async function candidateRequestDocs(db, riderData = {}) {
  const byId = new Map();
  const addDocs = (snapshot) => {
    snapshot.docs.forEach((doc) => byId.set(doc.id, doc));
  };
  const locality = riderLocality(riderData);
  const queries = [
    db.collection("deliveryRequests")
        .where("status", "==", "requested")
        .limit(REQUEST_SCAN_LIMIT)
        .get(),
  ];
  if (locality) {
    queries.unshift(
        db.collection("deliveryRequests")
            .where("pickupLocality", "==", locality)
            .limit(REQUEST_SCAN_LIMIT)
            .get(),
    );
  }
  const snapshots = await Promise.all(queries);
  snapshots.forEach(addDocs);
  return [...byId.values()].filter((doc) => {
    const delivery = doc.data() || {};
    const status = text(delivery.status).toLowerCase();
    if (status && !openStatuses.has(status)) return false;
    return hasPickupGeo(delivery);
  });
}

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

    const riderProfileDoc = await getFirestore().collection("riderProfiles").doc(riderId).get();
    const riderData = {
      ...(riderProfileDoc.exists ? riderProfileDoc.data() : {}),
      ...riderDoc.data(),
    };
    if (!riderData.position || !riderData.position.geopoint ||
        !Number.isFinite(Number(riderData.position.geopoint.latitude)) ||
        !Number.isFinite(Number(riderData.position.geopoint.longitude))) {
      throw new functions.https.HttpsError("failed-precondition", "Rider position not available");
    }

    const riderPosition = {
      latitude: riderData.position.geopoint.latitude,
      longitude: riderData.position.geopoint.longitude,
    };

    const requestDocs = await candidateRequestDocs(getFirestore(), riderData);

    // Calculate distances from rider to each request
    const requestsWithDistances = await Promise.all(
        requestDocs
            .filter((doc) => {
              const requestData = doc.data();
              if (!isDispatchable(requestData)) return false;
              return hasPickupGeo(requestData);
            })
            .map(async (doc) => {
              try {
                const requestData = doc.data();
                const privateDoc = await getFirestore()
                    .collection("irisPrivate")
                    .doc(requestData.requestId || doc.id)
                    .get();
                if (privateDoc.exists) {
                  requestData.irisPrivate = privateDoc.data();
                }
                if (!riderCanViewDispatch(riderData, requestData)) return null;
                if (!riderMatchesIris(riderData, requestData)) return null;
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
        .sort((a, b) => riderDispatchPriority(riderData, b) - riderDispatchPriority(riderData, a) ||
          dispatchPriority(b) - dispatchPriority(a) ||
          a.distanceFromRider - b.distanceFromRider)
        .slice(0, 5);

    return {
      riderId: riderId,
      riderPosition: riderPosition,
      nearestRequests: nearestRequests,
    };
  } catch (error) {
    if (error instanceof functions.https.HttpsError) throw error;
    console.error("Error in getNearbyRequests:", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
});

module.exports = getNearbyRequests;
module.exports._private = {candidateRequestDocs, riderLocality, deliveryLocality, hasPickupGeo, REQUEST_SCAN_LIMIT};
