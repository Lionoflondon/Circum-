/* eslint-disable max-len, require-jsdoc */
const {riderCallable} = require("./rider-app-check");

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

const getNearbyRequests = riderCallable(async (data, context) => {
  return require("./rider-offers").getOffers(data, context);
});

module.exports = getNearbyRequests;
module.exports._private = {candidateRequestDocs, riderLocality, deliveryLocality, hasPickupGeo, isLiveDispatchOffer, offerExclusionReason, REQUEST_SCAN_LIMIT};
