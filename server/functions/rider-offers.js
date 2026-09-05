/* eslint-disable max-len, require-jsdoc */
const functions = require("firebase-functions/v1");
const {getFirestore, Timestamp} = require("firebase-admin/firestore");
const {dispatchDecision, timestampMillis} = (() => {
  const p = require("./rider-presence-core");
  return {
    ...p,
    timestampMillis: (v) =>
      typeof v === "number" ?
        v :
        v && typeof v.toMillis === "function" ?
          v.toMillis() :
          v && v.seconds ?
            v.seconds * 1000 :
            0,
  };
})();
const {
  isDispatchable,
  riderCanViewDispatch,
  riderMatchesIris,
  dispatchPriority,
} = require("./iris-core");
const {pickRequiredVehicle} = require("./vehicle-dispatch");
const ACTIVE = [
  "accepted",
  "assigned",
  "navigating_to_pickup",
  "arrived_at_pickup",
  "waiting",
  "pickup_verification",
  "pickup_verified",
  "collected",
  "picked_up",
  "navigating_to_dropoff",
  "arrived_at_dropoff",
  "pin_required",
  "issue_reported",
];
const text = (v) => (typeof v === "string" ? v.trim() : "");
const number = (...values) => {
  for (const value of values) {
    if (value != null && Number.isFinite(Number(value))) return Number(value);
  }
  return null;
};
function locality(value, fallback) {
  const d = value && typeof value === "object" ? value : {};
  return (
    text(d.locality || d.area || d.city || d.postcode || fallback) ||
    "Location pending"
  );
}
function projection(id, d, expiresAt) {
  // Preserve the live getNearbyRequests privacy boundary: area-level locations before acceptance.
  const journey =
    (d.pricingBreakdown && d.pricingBreakdown.journey) || d.journey || {};
  const pickup = locality(
    d.pickupDetails || d.pickup || journey.pickup,
    d.pickupLocality,
  );
  const dropoff = locality(
    d.dropoffDetails || d.dropoff || journey.dropoff,
    d.dropoffLocality,
  );
  const parcel = d.parcel || {};
  const iris = d.iris || {};
  const recommendation = iris.recommendation || {};
  const miles = number(
    d.distanceMiles,
    journey.route && journey.route.distanceMiles,
  );
  const minutes = number(
    d.estimatedDurationMinutes,
    journey.route && journey.route.durationMinutes,
  );
  return {
    id,
    deliveryId: id,
    requestId: text(d.requestId) || id,
    projectionVersion: 2,
    pickupLocality: pickup,
    dropoffLocality: dropoff,
    pickupDetails: {locality: pickup},
    dropoffDetails: {locality: dropoff},
    riderEarning:
      number(d.riderEarning, d.riderPay, d.estimatedEarnings, d.riderShare, d.riderPayout, d.driverPayout) || 0,
    currency: text(d.currency) || "GBP",
    distanceText:
      text(d.distanceText || d.estimatedDistanceText) ||
      (miles == null ? null : `${miles.toFixed(1)} mi`),
    durationText:
      text(d.durationText || d.estimatedDurationText) ||
      (minutes == null ? null : `${Math.round(minutes)} min`),
    minimumVehicle: pickRequiredVehicle(d),
    vehicleType: pickRequiredVehicle(d),
    packageDescription:
      text(
        d.normalizedItemName ||
          parcel.itemName ||
          d.packageDescription ||
          parcel.description,
      ) || "Parcel",
    declaredWeightKg: number(d.declaredWeightKg, parcel.weightKg),
    weightKg: number(
      d.finalChargeableWeight,
      parcel.weightKg,
      d.declaredWeightKg,
    ),
    isHealthPlus: d.isHealthPlus === true || d.healthPlus === true,
    isGift: d.isGift === true || d.gift === true,
    isBusiness:
      d.isBusiness === true || d.businessMode === true || Boolean(d.businessId),
    businessMode: d.businessMode === true,
    isHeavyDuty: d.isHeavyDuty === true || d.isHeavy === true,
    requiresVanguard:
      d.requiresVanguard === true || d.vanguardProtocolEnabled === true,
    isScheduled:
      d.isScheduled === true ||
      Boolean(
        d.scheduledAt ||
          (d.deliveryTime && d.deliveryTime.type === "scheduled"),
      ),
    scheduledAt: timestampMillis(d.scheduledAt) || null,
    handlingSummary: (Array.isArray(recommendation.handlingFlags) ?
      recommendation.handlingFlags :
      []
    ).filter((v) => typeof v === "string"),
    iris: {
      category: text(iris.category || recommendation.category),
      confidence: text(iris.confidence),
      recommendation: {
        handlingFlags: (Array.isArray(recommendation.handlingFlags) ?
          recommendation.handlingFlags :
          []
        ).filter((v) => typeof v === "string"),
      },
    },
    offerExpiresAt: expiresAt,
    status: "requested",
  };
}
async function getOffers(_data, context, db = getFirestore()) {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Sign in to view offers.",
    );
  }
  const uid = context.auth.uid;
  const helpers = require("./get-avaliable-requests")._private;
  const localityProfile = await db.doc(`riderProfiles/${uid}`).get();
  const candidates = await helpers.candidateRequestDocs(
    db,
    localityProfile.data() || {},
  );
  return db.runTransaction(async (tx) => {
    const [profile, rider, presence, old] = await Promise.all([
      tx.get(db.doc(`riderProfiles/${uid}`)),
      tx.get(db.doc(`riders/${uid}`)),
      tx.get(db.doc(`riderPresence/${uid}`)),
      tx.get(db.collection(`riderOfferProjections/${uid}/offers`)),
    ]);
    const p = profile.data() || {};
    const r = rider.data() || {};
    const state = presence.data() || {};
    const combined = {...p, ...r};
    const now = Date.now();
    const decision = dispatchDecision({
      profile: combined,
      presence: state,
      now,
    });
    let active = Boolean(
      combined.activeDeliveryId ||
        combined.currentDeliveryId ||
        state.activeDeliveryId,
    );
    const activeResults = await Promise.all(
      ["riderId", "driverId", "assignedRiderId", "assignedDriverId"].map(
        (field) =>
          tx.get(
            db
              .collection("deliveryRequests")
              .where(field, "==", uid)
              .where("status", "in", ACTIVE)
              .limit(1),
          ),
      ),
    );
    active = active || activeResults.some((q) => !q.empty);
    const eligible =
      profile.exists &&
      rider.exists &&
      presence.exists &&
      decision.allowed &&
      state.dispatchEligible === true &&
      !active;
    const selected = [];
    if (eligible) {
      for (const candidate of candidates) {
        const current = await tx.get(candidate.ref);
        if (!current.exists) continue;
        const d = current.data();
        const privateDoc = await tx.get(
          db.doc(`irisPrivate/${d.requestId || current.id}`),
        );
        const classified = {
          ...d,
          ...(privateDoc.exists ? {irisPrivate: privateDoc.data()} : {}),
        };
        if (
          helpers.offerExclusionReason(d, now) ||
          !isDispatchable(classified) ||
          !riderCanViewDispatch(combined, classified) ||
          !riderMatchesIris(combined, classified)
        ) {
          continue;
        }
        selected.push({
          id: current.id,
          data: d,
          irisDocumentId: privateDoc.id,
          irisPrivate: privateDoc.exists ? privateDoc.data() : null,
          priority: dispatchPriority(classified),
        });
      }
    }
    selected.sort(
      (a, b) =>
        b.priority - a.priority ||
        timestampMillis(b.data.createdAt) - timestampMillis(a.data.createdAt),
    );
    const visible = selected.slice(0, 5);
    const keep = new Set(visible.map((v) => v.id));
    for (const doc of old.docs) {
      if (!keep.has(doc.id)) {
        tx.delete(doc.ref);
        tx.delete(db.doc(`riderOfferAuthorizations/${uid}/jobs/${doc.id}`));
      }
    }
    const expires = Math.min(
      now + 45000,
      timestampMillis(state.lastHeartbeatAt) + 120000,
      timestampMillis(
        (state.currentLocation && state.currentLocation.updatedAt) ||
          state.lastLocationAt,
      ) + 120000,
    );
    const offers = [];
    for (const item of visible) {
      const expiresAt = Math.min(
        expires,
        timestampMillis(
          item.data.offerExpiresAt ||
            item.data.dispatchExpiresAt ||
            item.data.expiresAt,
        ) || expires,
      );
      const data = projection(item.id, item.data, expiresAt);
      tx.set(db.doc(`riderOfferProjections/${uid}/offers/${item.id}`), {
        ...data,
        expiresAt: Timestamp.fromMillis(expiresAt),
      });
      // Private authorization snapshots invalidate immediately on any eligibility or delivery change.
      // These documents are never readable by clients and are never included in callable responses.
      tx.set(db.doc(`riderOfferAuthorizations/${uid}/jobs/${item.id}`), {
        profile: p,
        rider: r,
        presence: state,
        delivery: item.data,
        irisDocumentId: item.irisDocumentId,
        irisPrivate: item.irisPrivate,
        expiresAt: Timestamp.fromMillis(expiresAt),
      });
      offers.push(data);
    }
    return {
      riderId: uid,
      nearestRequests: offers,
      expiresAt: expires,
      eligible: Boolean(eligible),
    };
  });
}
module.exports = {getOffers, projection};
