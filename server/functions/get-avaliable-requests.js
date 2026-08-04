/* eslint-disable max-len, require-jsdoc */
const functions = require("firebase-functions/v1");
const {getFirestore} = require("firebase-admin/firestore");
const {dispatchPriority, isDispatchable, riderCanViewDispatch, riderDispatchEligibilityReason, riderDispatchPriority, riderMatchesIris} = require("./iris-core");
const {loadFounderTestAccount} = require("./founder-authority");
const riderPresenceCore = require("./rider-presence-core");

const REQUEST_SCAN_LIMIT = 100;
const openStatuses = new Set(["requested", "pending", "broadcast", "broadcasted", "awaiting_rider", "finding_rider"]);
const terminalStatuses = new Set(["accepted", "assigned", "collected", "in_transit", "delivered", "completed", "cancelled", "canceled", "expired", "failed", "blocked"]);
const openMatchingStatuses = new Set(["available", "requested", "broadcast", "broadcasted"]);
const openDispatchStatuses = new Set(["requested", "available", "broadcast", "broadcasted", "queued", "waiting"]);
const paidStatuses = new Set(["", "paid", "succeeded", "payment_confirmed", "confirmed", "roth_paid", "stripe_paid"]);
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

function millis(value) {
  if (!value) return 0;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (Number.isFinite(Number(value))) return Number(value);
  if (value.seconds !== undefined) return Number(value.seconds) * 1000;
  const parsed = Date.parse(`${value}`);
  return Number.isFinite(parsed) ? parsed : 0;
}

function deliveryCreatedMillis(delivery = {}) {
  return millis(delivery.createdAt || delivery.created_at || delivery.bookingCreatedAt || delivery.updatedAt);
}

function offerExpiryMillis(delivery = {}) {
  return millis(delivery.offerExpiresAt || delivery.dispatchExpiresAt || delivery.expiresAt || delivery.matchingExpiresAt);
}

function assignedRiderId(delivery = {}) {
  return text(delivery.riderId || delivery.driverId || delivery.assignedRider || delivery.assignedRiderId || delivery.assignedDriverId || delivery.courierId);
}

function offerExclusionReason(delivery = {}, now = Date.now()) {
  const status = text(delivery.status).toLowerCase();
  const deliveryStatus = text(delivery.deliveryStatus || delivery.deliveryStage).toLowerCase();
  const matchingStatus = text(delivery.matchingStatus).toLowerCase();
  const dispatchStatus = text(delivery.dispatchStatus).toLowerCase();
  const paymentStatus = text(delivery.paymentStatus || delivery.paymentState).toLowerCase();
  const assigned = assignedRiderId(delivery);
  const expiry = offerExpiryMillis(delivery);

  if ([status, deliveryStatus, matchingStatus, dispatchStatus].some((value) => terminalStatuses.has(value))) return "terminal_status";
  if (assigned) return "already_assigned";
  if (expiry && expiry <= now) return "expired_offer";
  if (!paidStatuses.has(paymentStatus)) return "payment_not_confirmed";
  if (matchingStatus && !openMatchingStatuses.has(matchingStatus)) return "matching_not_open";
  if (dispatchStatus && !openDispatchStatuses.has(dispatchStatus)) return "dispatch_not_open";
  if (status && !openStatuses.has(status) && matchingStatus !== "available" && dispatchStatus !== "requested") return "status_not_open";
  if (!hasPickupGeo(delivery)) return "missing_pickup_geo";
  return "";
}

function isLiveDispatchOffer(delivery = {}, now = Date.now()) {
  return offerExclusionReason(delivery, now) === "";
}

async function candidateRequestDocs(db, riderData = {}) {
  const byId = new Map();
  const addDocs = (snapshot) => {
    snapshot.docs.forEach((doc) => byId.set(doc.id, doc));
  };
  const locality = riderLocality(riderData);
  const queries = [
    db.collection("deliveryRequests")
        .where("matchingStatus", "==", "available")
        .limit(REQUEST_SCAN_LIMIT)
        .get(),
    db.collection("deliveryRequests")
        .where("dispatchStatus", "==", "requested")
        .limit(REQUEST_SCAN_LIMIT)
        .get(),
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
  return [...byId.values()]
      .filter((doc) => isLiveDispatchOffer(doc.data() || {}))
      .sort((a, b) => deliveryCreatedMillis(b.data() || {}) - deliveryCreatedMillis(a.data() || {}));
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
    const riderPresenceDoc = await getFirestore().collection("riderPresence").doc(riderId).get();
    const riderData = {
      ...(riderProfileDoc.exists ? riderProfileDoc.data() : {}),
      ...riderDoc.data(),
    };
    const founderTestAccount = await loadFounderTestAccount(getFirestore(), riderId);
    if (founderTestAccount) {
      riderData.founderTestAccount = founderTestAccount;
    }
    const riderPresence = riderPresenceDoc.exists ? riderPresenceDoc.data() : {};
    if (!riderPresenceCore.canReceiveDispatch({profile: riderData, presence: riderPresence})) {
      throw new functions.https.HttpsError("failed-precondition", "Rider presence is not dispatch-ready");
    }
    const currentLocation = riderPresence.currentLocation || {};
    if (!Number.isFinite(Number(currentLocation.latitude)) ||
        !Number.isFinite(Number(currentLocation.longitude))) {
      throw new functions.https.HttpsError("failed-precondition", "Rider position not available");
    }

    const riderPosition = {
      latitude: Number(currentLocation.latitude),
      longitude: Number(currentLocation.longitude),
    };

    const requestDocs = await candidateRequestDocs(getFirestore(), riderData);
    console.info("rider_offer_scan", {
      riderId,
      scanned: requestDocs.length,
      riderLocality: riderLocality(riderData),
      candidates: requestDocs.slice(0, 10).map((doc) => {
        const delivery = doc.data() || {};
        return {
          bookingId: text(delivery.bookingId || delivery.requestId || doc.id),
          deliveryId: doc.id,
          senderId: text(delivery.senderId || delivery.userId || delivery.customerId),
          dispatchId: text(delivery.dispatchId || delivery.dispatchRunId),
          offerCreatedAt: deliveryCreatedMillis(delivery),
          offerExpiresAt: offerExpiryMillis(delivery),
          status: text(delivery.status),
          matchingStatus: text(delivery.matchingStatus),
          dispatchStatus: text(delivery.dispatchStatus),
        };
      }),
    });

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
                const exclusion = offerExclusionReason(requestData);
                if (exclusion) {
                  console.info("rider_offer_excluded", {
                    riderId,
                    bookingId: text(requestData.bookingId || requestData.requestId || doc.id),
                    deliveryId: doc.id,
                    senderId: text(requestData.senderId || requestData.userId || requestData.customerId),
                    dispatchId: text(requestData.dispatchId || requestData.dispatchRunId),
                    reason: exclusion,
                  });
                  return null;
                }
                const privateDoc = await getFirestore()
                    .collection("irisPrivate")
                    .doc(requestData.requestId || doc.id)
                    .get();
                if (privateDoc.exists) {
                  requestData.irisPrivate = privateDoc.data();
                }
                if (!riderCanViewDispatch(riderData, requestData)) {
                  console.info("rider_offer_excluded", {riderId, bookingId: text(requestData.bookingId || requestData.requestId || doc.id), deliveryId: doc.id, reason: riderDispatchEligibilityReason(riderData), eligibility: {
                    approvalStatus: riderData.approvalStatus,
                    verificationStatus: riderData.verificationStatus,
                    adminApprovalStatus: riderData.adminApprovalStatus,
                    accountStatus: riderData.accountStatus,
                    onboardingStatus: riderData.onboardingStatus,
                  }});
                  return null;
                }
                if (!riderMatchesIris(riderData, requestData)) {
                  console.info("rider_offer_excluded", {riderId, bookingId: text(requestData.bookingId || requestData.requestId || doc.id), deliveryId: doc.id, reason: "iris_mismatch"});
                  return null;
                }
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
          deliveryCreatedMillis(b) - deliveryCreatedMillis(a) ||
          a.distanceFromRider - b.distanceFromRider)
        .slice(0, 5);
    console.info("rider_offer_returned", {
      riderId,
      returned: nearestRequests.map((request) => ({
        bookingId: text(request.bookingId || request.requestId || request.id),
        deliveryId: request.id,
        senderId: text(request.senderId || request.userId || request.customerId),
        dispatchId: text(request.dispatchId || request.dispatchRunId),
        offerCreatedAt: deliveryCreatedMillis(request),
        offerExpiresAt: offerExpiryMillis(request),
      })),
    });

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
module.exports._private = {candidateRequestDocs, riderLocality, deliveryLocality, hasPickupGeo, isLiveDispatchOffer, offerExclusionReason, REQUEST_SCAN_LIMIT};
