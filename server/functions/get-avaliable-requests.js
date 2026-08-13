/* eslint-disable max-len, require-jsdoc */
const functions = require("firebase-functions/v1");
const {getFirestore} = require("firebase-admin/firestore");
const {dispatchPriority, isDispatchable, riderCanViewDispatch, riderDispatchPriority, riderMatchesIris} = require("./iris-core");
const presenceCore = require("./rider-presence-core");

const REQUEST_SCAN_LIMIT = 100;
const openStatuses = new Set(["requested", "pending", "broadcast", "broadcasted", "awaiting_rider", "finding_rider"]);
const terminalStatuses = new Set(["accepted", "assigned", "collected", "in_transit", "delivered", "completed", "cancelled", "canceled", "expired", "failed", "blocked"]);
const openMatchingStatuses = new Set(["available", "requested", "broadcast", "broadcasted"]);
const openDispatchStatuses = new Set(["requested", "available", "broadcast", "broadcasted", "queued", "waiting"]);
const paidStatuses = new Set(["", "paid", "succeeded", "payment_confirmed", "confirmed", "roth_paid", "stripe_paid"]);
const text = (value) => `${value || ""}`.trim();

function finiteNumber(...values) {
  for (const value of values) {
    const number = Number(value);
    if (Number.isFinite(number) && number >= 0) return number;
  }
  return null;
}

function weightBand(weightKg) {
  if (!Number.isFinite(weightKg)) return "review_required";
  if (weightKg <= 5) return "0-5 kg";
  if (weightKg <= 10) return ">5-10 kg";
  if (weightKg <= 20) return ">10-20 kg";
  if (weightKg <= 40) return ">20-40 kg";
  return ">40 kg";
}

function safeLocality(address = {}, fallback = "") {
  return text(address.locality || address.city || fallback) || "Location pending";
}

function riderOfferProjection(deliveryId, delivery = {}, distanceFromRider = 0) {
  const journey = delivery.pricingBreakdown && delivery.pricingBreakdown.journey || delivery.journey || {};
  const pickup = journey.pickup || {};
  const dropoff = journey.dropoff || {};
  const parcel = delivery.parcel || {};
  const iris = delivery.iris || delivery.irisDeliveryEstimate || {};
  const recommendation = iris.recommendation || {};
  const chargeableWeightKg = finiteNumber(
      delivery.pricingBreakdown && delivery.pricingBreakdown.weightKg,
      delivery.finalChargeableWeight,
      delivery.finalPricingWeightKg,
  );
  const ascribedWeightKg = finiteNumber(
      recommendation.estimatedWeightKg,
      delivery.irisEstimatedWeight,
      delivery.irisEstimatedWeightKg,
  );
  const declaredWeightKg = finiteNumber(parcel.weightKg, delivery.declaredWeightKg);
  const quantity = Math.max(1, Math.round(finiteNumber(iris.quantity, parcel.quantity, 1) || 1));
  const route = journey.route || {};
  const routeMiles = finiteNumber(route.distanceMiles, delivery.distanceMiles);
  const routeMinutes = finiteNumber(route.durationMinutes, delivery.estimatedDurationMinutes);
  const pickupLocality = safeLocality(pickup, delivery.pickupLocality);
  const dropoffLocality = safeLocality(dropoff, delivery.dropoffLocality);
  return {
    projectionVersion: 1,
    authority: "backend_rider_offer_projection",
    id: deliveryId,
    requestId: text(delivery.requestId || deliveryId),
    pickupLocality,
    dropoffLocality,
    directionText: `${pickupLocality} to ${dropoffLocality}`,
    distanceFromRiderKm: Math.round(Number(distanceFromRider || 0) * 100) / 100,
    routeDistanceMiles: routeMiles,
    routeDurationMinutes: routeMinutes,
    distanceText: routeMiles == null ? null : `${routeMiles.toFixed(1)} mi`,
    durationText: routeMinutes == null ? null : `${Math.round(routeMinutes)} min`,
    pickupAccessWarning: text(delivery.pickupDetails && delivery.pickupDetails.moreInformation) ?
      "Collection access notes available after acceptance" : null,
    dropoffAccessWarning: text(delivery.dropoffDetails && delivery.dropoffDetails.moreInformation) ?
      "Drop-off access notes available after acceptance" : null,
    roadChargeContext: text(delivery.roadChargeContext || delivery.pricingBreakdown && delivery.pricingBreakdown.roadChargeContext),
    scheduledCollectionTime: delivery.deliveryTime || null,
    serviceSpeed: text(delivery.selectedServiceLevel || delivery.serviceLevel || delivery.selectedSpeed || "standard"),
    item: {
      canonicalItem: text(iris.itemName || delivery.normalizedItemName || parcel.itemName || "Parcel"),
      category: text(iris.category || recommendation.category),
      quantity,
      senderDescription: text(parcel.description || delivery.packageDescription),
      declaredWeightKg,
      ascribedWeightKg,
      chargeableWeightKg,
      weightBand: weightBand(chargeableWeightKg),
      sizeClass: text(recommendation.sizeClass || iris.sizeClass || parcel.sizeClass),
      dimensions: recommendation.dimensions || iris.dimensions || parcel.dimensions || null,
      fragile: parcel.fragile === true || iris.fragile === true,
      highValue: parcel.highValue === true || iris.highValue === true,
      vanguardRequired: delivery.requiresVanguard === true,
      specialistRequired: delivery.specialistRequired === true || recommendation.specialistRequired === true,
      requiredVehicle: text(recommendation.vehicleType || delivery.minimumVehicle || delivery.vehicleType),
      liftWarning: text(recommendation.liftWarning || delivery.liftWarning),
      multiItem: quantity > 1,
      photoEvidenceStatus: text(delivery.irisPhotoAnalysisId) ? "verified_analysis" : "not_supplied",
      confidence: text(iris.confidence || recommendation.confidence),
      reviewState: text(delivery.irisReviewStatus || "canonical"),
      pickupConfirmationRequired: delivery.weightVerificationRequired === true || delivery.requiresVerification === true,
    },
    riderEarning: finiteNumber(delivery.riderEarning, delivery.riderPayout, delivery.driverPayout) || 0,
    currency: text(delivery.currency || "GBP").toUpperCase(),
    warningFlags: {
      vanguard: delivery.requiresVanguard === true,
      healthPlus: delivery.isHealthPlus === true,
      gift: delivery.isGift === true,
      business: delivery.isBusiness === true || delivery.businessMode === true,
      heavyDuty: delivery.isHeavyDuty === true,
      scheduled: Boolean(delivery.scheduledAt || delivery.deliveryTime && delivery.deliveryTime.type === "scheduled"),
    },
  };
}

function riderAssignedProjection(deliveryId, delivery = {}) {
  const offer = riderOfferProjection(deliveryId, delivery, 0);
  const pickup = delivery.pickupDetails || {};
  const dropoff = delivery.dropoffDetails || {};
  return {
    ...offer,
    authority: "backend_rider_assigned_projection",
    status: text(delivery.status || delivery.deliveryStatus),
    deliveryStage: text(delivery.deliveryStage || delivery.deliveryStatus || delivery.status),
    pickupAddress: text(pickup.address || delivery.pickupAddress),
    dropoffAddress: text(dropoff.address || delivery.dropoffAddress),
    pickupAccessNotes: text(pickup.moreInformation),
    dropoffAccessNotes: text(dropoff.moreInformation),
    contact: {
      method: "circum_relay",
      chatId: text(delivery.requestId || deliveryId),
      phoneAvailable: false,
      emailAvailable: false,
    },
    verificationRequired: delivery.verificationRequired === true || delivery.requiresVerification === true,
    deliveryPhotoRequired: delivery.deliveryPhotoRequired === true || delivery.proofPhotoRequired === true,
    pinRequired: delivery.pinRequired === true || delivery.requiresVanguard === true,
  };
}

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
    if (!context.app) {
      throw new functions.https.HttpsError("failed-precondition", "Security verification is required.");
    }

    const riderId = context.auth.uid;

    // Get rider's current position
    const riderDoc = await getFirestore().collection("riders").doc(riderId).get();
    if (!riderDoc.exists) {
      throw new functions.https.HttpsError("not-found", "Rider not found");
    }

    const riderProfileDoc = await getFirestore().collection("riderProfiles").doc(riderId).get();
    const presenceDoc = await getFirestore().collection("riderPresence").doc(riderId).get();
    const riderData = {
      ...(riderProfileDoc.exists ? riderProfileDoc.data() : {}),
      ...riderDoc.data(),
    };
    const presence = presenceDoc.exists ? presenceDoc.data() : {};
    const founderRider = context.auth.token && context.auth.token.founderRider === true;
    if (!founderRider && !presenceCore.canReceiveDispatch({profile: riderData, presence})) {
      return {riderId, riderPosition: null, nearestRequests: [], reason: "presence_not_ready"};
    }
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
                  console.info("rider_offer_excluded", {riderId, bookingId: text(requestData.bookingId || requestData.requestId || doc.id), deliveryId: doc.id, reason: "rank_or_visibility"});
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
                  projection: riderOfferProjection(doc.id, requestData, distance),
                  source: requestData,
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
        .sort((a, b) => riderDispatchPriority(riderData, b.source) - riderDispatchPriority(riderData, a.source) ||
          dispatchPriority(b.source) - dispatchPriority(a.source) ||
          deliveryCreatedMillis(b.source) - deliveryCreatedMillis(a.source) ||
          a.distanceFromRider - b.distanceFromRider)
        .slice(0, 5)
        .map((request) => request.projection);
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
module.exports._private = {candidateRequestDocs, riderLocality, deliveryLocality, hasPickupGeo, isLiveDispatchOffer, offerExclusionReason, riderOfferProjection, riderAssignedProjection, weightBand, REQUEST_SCAN_LIMIT};
