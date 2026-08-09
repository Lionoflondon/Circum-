/* eslint-disable max-len, require-jsdoc */
const riderPresenceCore = require("./rider-presence-core");
const {riderVehicleMatchesRequest} = require("./vehicle-dispatch");

const DEFAULT_MAX_DISPATCH_RADIUS_KM = 25;
const BLOCKED_ACCOUNT_STATUSES = new Set(["suspended", "frozen", "closed", "rejected", "disabled"]);

const text = (value) => `${value || ""}`.trim();
const lower = (value) => text(value).toLowerCase();

function coordinate(value = {}) {
  const source = value.geopoint || value.location || value.coordinates || value;
  const latitude = Number(source.latitude ?? source.lat);
  const longitude = Number(source.longitude ?? source.lng ?? source.lon);
  return Number.isFinite(latitude) && Number.isFinite(longitude) ? {latitude, longitude} : null;
}

function pickupCoordinate(delivery = {}) {
  return coordinate(
      delivery.pickupPosition && delivery.pickupPosition.geopoint ||
      delivery.pickupPosition ||
      delivery.pickupCoordinates ||
      delivery.pickupLocation,
  );
}

function riderCoordinate(presence = {}) {
  return coordinate(presence.currentLocation || presence.location || presence.riderLiveLocation);
}

function distanceKm(a, b) {
  if (!a || !b) return Number.POSITIVE_INFINITY;
  const toRadians = (degrees) => degrees * Math.PI / 180;
  const earthRadiusKm = 6371;
  const dLat = toRadians(b.latitude - a.latitude);
  const dLon = toRadians(b.longitude - a.longitude);
  const value = Math.sin(dLat / 2) ** 2 +
    Math.cos(toRadians(a.latitude)) * Math.cos(toRadians(b.latitude)) *
    Math.sin(dLon / 2) ** 2;
  return earthRadiusKm * 2 * Math.atan2(Math.sqrt(value), Math.sqrt(1 - value));
}

function accountEligibilityDecision(profile = {}) {
  if (profile.dispatchEligible !== true) return {eligible: false, reason: "dispatch_not_eligible"};
  if (lower(profile.approvalStatus) !== "approved") return {eligible: false, reason: "approval_not_approved"};
  if (!new Set(["approved", "verified"]).has(lower(profile.verificationStatus))) {
    return {eligible: false, reason: "verification_not_approved"};
  }
  if (lower(profile.onboardingStatus) !== "approved") return {eligible: false, reason: "onboarding_not_approved"};
  if (profile.documentsVerified !== true) return {eligible: false, reason: "documents_not_verified"};
  if (profile.vehicleVerified !== true) return {eligible: false, reason: "vehicle_not_verified"};
  if (profile.suspended === true || profile.isSuspended === true || profile.isFrozen === true || profile.isClosed === true) {
    return {eligible: false, reason: "account_blocked"};
  }
  if ([profile.accountStatus, profile.riderStatus, profile.driverStatus].some((status) => BLOCKED_ACCOUNT_STATUSES.has(lower(status)))) {
    return {eligible: false, reason: "account_blocked"};
  }
  return {eligible: true, reason: "eligible"};
}

function presenceEligibilityDecision({riderId, presence = {}, now = Date.now()}) {
  const owner = text(presence.riderId || presence.uid || presence.userId);
  if (owner && owner !== riderId) return {eligible: false, reason: "location_owner_mismatch"};
  if (presence.isOnline !== true) return {eligible: false, reason: "offline"};
  if (lower(presence.availabilityStatus) !== "available") return {eligible: false, reason: "not_available"};
  if (presence.busy === true) return {eligible: false, reason: "busy"};
  if (text(presence.activeDeliveryId || presence.currentDeliveryId)) return {eligible: false, reason: "active_delivery"};
  if (presence.dispatchEligible !== true) return {eligible: false, reason: "presence_not_dispatch_eligible"};
  const heartbeat = riderPresenceCore.timestampMillis(presence.lastHeartbeatAt);
  if (!heartbeat || heartbeat > now + 30000 || now - heartbeat > riderPresenceCore.STALE_HEARTBEAT_MS) {
    return {eligible: false, reason: "stale_heartbeat"};
  }
  if (!riderPresenceCore.gpsHealthy({presence, now})) {
    const location = riderCoordinate(presence);
    return {eligible: false, reason: location ? "stale_or_unhealthy_location" : "location_missing"};
  }
  return {eligible: true, reason: "eligible"};
}

function serviceName(delivery = {}) {
  const iris = delivery.irisPrivate || delivery.iris || {};
  return lower(
      iris.workflow ||
      iris.recommendation && iris.recommendation.workflow ||
      delivery.workflow ||
      delivery.sourceModule ||
      delivery.serviceType ||
      delivery.productType ||
      "standard",
  ).replace(/[^a-z0-9]+/g, "_");
}

function approvedServices(profile = {}) {
  const values = [
    profile.approvedServiceTypes,
    profile.dispatchServiceTypes,
    profile.serviceTypes,
    profile.approvedServices,
  ].flatMap((value) => Array.isArray(value) ? value : []);
  const result = new Set(values.map((value) => lower(value).replace(/[^a-z0-9]+/g, "_")));
  result.add("standard");
  result.add("business");
  if (profile.healthDispatchEligible === true || profile.healthPlusEligible === true || profile.healthCertified === true) {
    result.add("health");
    result.add("health_plus");
  }
  if (profile.giftDispatchEligible === true || profile.giftEligible === true || profile.giftCertified === true) {
    result.add("gift");
    result.add("gifts");
  }
  return result;
}

function serviceEligibilityDecision(profile = {}, delivery = {}) {
  const service = serviceName(delivery);
  const normalized = service === "health" || service === "health_" ? "health_plus" :
    service === "gift" ? "gifts" : service;
  if (!approvedServices(profile).has(normalized)) {
    return {eligible: false, reason: `service_not_approved_${normalized}`, service: normalized};
  }
  const iris = delivery.irisPrivate || delivery.iris || {};
  const matching = iris.internal && iris.internal.riderMatching || delivery.matchingRules || {};
  if (matching.requiresTwoPerson === true && profile.twoPersonLift !== true && profile.twoPersonCapability !== true) {
    return {eligible: false, reason: "two_person_capability_required", service: normalized};
  }
  return {eligible: true, reason: "eligible", service: normalized};
}

function dispatchEligibilityDecision({
  riderId,
  profile = {},
  presence = {},
  delivery = {},
  now = Date.now(),
  maxRadiusKm = DEFAULT_MAX_DISPATCH_RADIUS_KM,
}) {
  const account = accountEligibilityDecision(profile);
  if (!account.eligible) return {...account, riderId};
  const presenceDecision = presenceEligibilityDecision({riderId, presence, now});
  if (!presenceDecision.eligible) return {...presenceDecision, riderId};
  const excludedRiders = [delivery.ignoredByRiders, delivery.rejectedByRiders]
      .flatMap((value) => Array.isArray(value) ? value : [])
      .map(text);
  if (excludedRiders.includes(riderId)) {
    return {eligible: false, reason: "rider_previously_declined", riderId};
  }
  if (!riderVehicleMatchesRequest(profile, delivery)) {
    return {eligible: false, reason: "vehicle_incompatible", riderId};
  }
  const service = serviceEligibilityDecision(profile, delivery);
  if (!service.eligible) return {...service, riderId};
  const pickup = pickupCoordinate(delivery);
  if (!pickup) return {eligible: false, reason: "pickup_location_missing", riderId};
  const location = riderCoordinate(presence);
  if (!location) return {eligible: false, reason: "location_missing", riderId};
  const candidateDistanceKm = distanceKm(location, pickup);
  if (!Number.isFinite(candidateDistanceKm) || candidateDistanceKm > maxRadiusKm) {
    return {eligible: false, reason: "outside_dispatch_radius", riderId, distanceKm: candidateDistanceKm};
  }
  return {
    eligible: true,
    reason: "eligible",
    riderId,
    service: service.service,
    location,
    pickup,
    distanceKm: candidateDistanceKm,
    maxRadiusKm,
  };
}

function safePosition(value) {
  const point = coordinate(value);
  return point ? {geopoint: point} : null;
}

function safeContactLocation(value = {}, fallbackAddress = "", fallbackPosition = null) {
  const source = value && typeof value === "object" ? value : {};
  return {
    address: text(source.address || source.displayAddress || fallbackAddress),
    subAddress: text(source.subAddress || source.addressLine2),
    locality: text(source.locality || source.city || source.town),
    postcode: text(source.postcode || source.postalCode),
    position: safePosition(source.position || fallbackPosition),
  };
}

function safePerson(value = {}, fallbackName = "", fallbackPhone = "") {
  const source = value && typeof value === "object" ? value : {};
  return {
    name: text(source.name || source.fullName || fallbackName),
    phone: text(source.phone || source.phoneNumber || fallbackPhone),
  };
}

function riderOfferProjection(deliveryId, delivery = {}, distanceFromRiderKm = 0) {
  const pickupDetails = safeContactLocation(
      delivery.pickupDetails || delivery.pickup,
      delivery.pickupAddress,
      delivery.pickupPosition || delivery.pickupCoordinates,
  );
  const dropoffDetails = safeContactLocation(
      delivery.dropoffDetails || delivery.dropoff,
      delivery.dropoffAddress,
      delivery.dropOffPosition || delivery.dropoffPosition || delivery.dropoffCoordinates,
  );
  const payout = Number(delivery.riderEarning ?? delivery.riderPayout ?? delivery.driverPayout ?? 0);
  const summary = delivery.driverJobSummary && typeof delivery.driverJobSummary === "object" ? delivery.driverJobSummary : {};
  const parcel = delivery.parcel && typeof delivery.parcel === "object" ? delivery.parcel : {};
  return {
    id: deliveryId,
    requestId: text(delivery.requestId || delivery.bookingId || deliveryId),
    bookingId: text(delivery.bookingId || delivery.requestId || deliveryId),
    status: text(delivery.status),
    matchingStatus: text(delivery.matchingStatus),
    dispatchStatus: text(delivery.dispatchStatus),
    pickupDetails,
    dropoffDetails,
    pickupAddress: pickupDetails.address,
    dropoffAddress: dropoffDetails.address,
    pickupPosition: pickupDetails.position,
    dropoffPosition: dropoffDetails.position,
    vehicleType: text(delivery.vehicleType || delivery.requiredVehicle || delivery.vehicleRequirement),
    requiredVehicle: text(delivery.requiredVehicle || delivery.vehicleRequirement || delivery.vehicleType),
    selectedServiceLevel: text(delivery.selectedServiceLevel || delivery.serviceLevel || delivery.speed),
    serviceLevel: text(delivery.serviceLevel || delivery.selectedServiceLevel || delivery.speed),
    speed: text(delivery.speed || delivery.selectedServiceLevel || delivery.serviceLevel),
    packageType: text(delivery.packageType || parcel.packageType || parcel.type),
    packageDescription: text(delivery.packageDescription || parcel.description || parcel.itemName),
    packageDimensions: text(delivery.packageDimensions || delivery.dimensions || parcel.dimensions),
    weightKg: Number(delivery.finalPricingWeightKg ?? delivery.finalChargeableWeight ?? delivery.weightKg ?? parcel.weightKg ?? 0),
    scheduledAt: delivery.scheduledAt || delivery.scheduledJourneyAt || null,
    pickupWindow: delivery.pickupWindow || delivery.scheduledPickupWindow || null,
    riderEarning: Number.isFinite(payout) ? payout : 0,
    riderPayout: Number.isFinite(payout) ? payout : 0,
    driverPayout: Number.isFinite(payout) ? payout : 0,
    price: Number.isFinite(payout) ? payout : 0,
    currency: text(delivery.currency || "GBP").toUpperCase(),
    driverJobSummary: {
      pickupDisplay: text(summary.pickupDisplay || pickupDetails.address),
      dropoffDisplay: text(summary.dropoffDisplay || dropoffDetails.address),
      estimatedDistanceMiles: Number(summary.estimatedDistanceMiles || delivery.routeDistanceMiles || delivery.distanceMiles || 0),
      estimatedDurationMinutes: Number(summary.estimatedDurationMinutes || delivery.estimatedDurationMinutes || 0),
      driverPayout: Number.isFinite(payout) ? payout : 0,
      vehicleType: text(summary.vehicleType || delivery.vehicleType || delivery.requiredVehicle),
      serviceLevel: text(summary.serviceLevel || delivery.serviceLevel || delivery.selectedServiceLevel),
      packageType: text(summary.packageType || delivery.packageType || parcel.type),
      packageDescription: text(summary.packageDescription || delivery.packageDescription || parcel.description),
    },
    requiresVanguard: delivery.requiresVanguard === true || delivery.vanguardProtocolEnabled === true,
    isHealthPlus: serviceName(delivery).startsWith("health"),
    isGift: serviceName(delivery).startsWith("gift"),
    isBusiness: serviceName(delivery).startsWith("business"),
    createdAt: delivery.createdAt || delivery.requestedAt || null,
    offerExpiresAt: delivery.offerExpiresAt || delivery.dispatchExpiresAt || delivery.expiresAt || null,
    distanceFromRider: Number(distanceFromRiderKm),
  };
}

function riderAssignedJobProjection(deliveryId, delivery = {}, {completed = false} = {}) {
  const projection = riderOfferProjection(deliveryId, delivery, 0);
  const summary = delivery.driverJobSummary && typeof delivery.driverJobSummary === "object" ? delivery.driverJobSummary : {};
  const riderBaseShare = Number(delivery.riderBaseShare ?? summary.riderBaseShare ?? 0);
  const riderLabourShare = Number(delivery.riderLabourShare ?? summary.riderLabourShare ?? 0);
  const assistedFee = Number(delivery.assistedFee ?? summary.assistedFee ?? 0);
  const heavyDutyFee = Number(delivery.heavyDutyFee ?? summary.heavyDutyFee ?? 0);
  const twoPersonFee = Number(delivery.twoPersonFee ?? summary.twoPersonFee ?? 0);
  const tipAmount = Number(delivery.tipAmount ?? delivery.riderTip ?? summary.tipAmount ?? 0);

  const operational = {
    ...projection,
    pickupAccess: text(delivery.pickupAccess),
    dropoffAccess: text(delivery.dropoffAccess),
    normalizedItemName: text(delivery.normalizedItemName),
    customerDeclaredWeight: Number(delivery.customerDeclaredWeight ?? delivery.senderEnteredWeightKg ?? 0),
    irisEstimatedWeight: Number(delivery.irisEstimatedWeight ?? delivery.irisEstimatedWeightKg ?? 0),
    finalWeightUsed: Number(delivery.finalWeightUsed ?? delivery.finalChargeableWeight ?? delivery.confirmedWeightKg ?? projection.weightKg ?? 0),
    weightCategory: text(delivery.weightCategory || delivery.confirmedWeightBand),
    irisConfidenceScore: text(delivery.irisConfidenceScore || delivery.irisWeightConfidence),
    irisWeightSource: text(delivery.irisWeightSource || summary.irisWeightSource),
    weightReviewRequired: delivery.weightReviewRequired === true,
    weightVerificationRequired: delivery.weightVerificationRequired === true,
    vanguardEnabled: delivery.vanguardEnabled === true ||
      delivery.requiresVanguard === true ||
      delivery.vanguardProtocolEnabled === true ||
      delivery.vanguardProtection && delivery.vanguardProtection.enabled === true,
    collectionPinVerified: delivery.collectionPinVerified === true,
    deliveryPinVerified: delivery.deliveryPinVerified === true,
    riderBaseShare: Number.isFinite(riderBaseShare) ? riderBaseShare : 0,
    riderLabourShare: Number.isFinite(riderLabourShare) ? riderLabourShare : 0,
    assistedFee: Number.isFinite(assistedFee) ? assistedFee : 0,
    heavyDutyFee: Number.isFinite(heavyDutyFee) ? heavyDutyFee : 0,
    twoPersonFee: Number.isFinite(twoPersonFee) ? twoPersonFee : 0,
    tipAmount: Number.isFinite(tipAmount) ? tipAmount : 0,
    scheduledPickupDate: delivery.scheduledPickupDate || null,
    scheduledPickupWindow: delivery.scheduledPickupWindow || null,
    deliveryTimingType: text(delivery.deliveryTimingType),
    deliveredAt: completed ? delivery.deliveredAt || delivery.completedAt || null : null,
    completedAt: completed ? delivery.completedAt || delivery.deliveredAt || null : null,
    proofOfDelivery: completed ? {
      available: Boolean(delivery.proofOfDelivery || delivery.deliveryProof || delivery.completionProof),
      collectionPinVerified: delivery.collectionPinVerified === true,
      deliveryPinVerified: delivery.deliveryPinVerified === true,
    } : null,
  };

  if (!completed) {
    const sender = safePerson(
        delivery.senderDetails,
        delivery.senderName || summary.senderName,
        delivery.senderPhone || summary.senderPhone,
    );
    const receiver = safePerson(
        delivery.receiverDetails || delivery.recipient,
        delivery.receiverName || summary.receiverName,
        delivery.receiverPhone || summary.receiverPhone,
    );
    const collection = safePerson(
        delivery.collectionContact,
        delivery.collectionContactName || summary.collectionContactName,
        delivery.collectionContactPhone || summary.collectionContactPhone,
    );
    operational.senderDetails = sender;
    operational.receiverDetails = receiver;
    operational.collectionContact = {
      ...collection,
      differentFromSender: delivery.collectionContactDifferent === true ||
        delivery.collectionContact && delivery.collectionContact.differentFromSender === true,
    };
  }

  operational.driverJobSummary = {
    ...projection.driverJobSummary,
    finalWeightUsed: operational.finalWeightUsed,
    confirmedWeightBand: operational.weightCategory,
    riderBaseShare: operational.riderBaseShare,
    riderLabourShare: operational.riderLabourShare,
    assistedFee: operational.assistedFee,
    heavyDutyFee: operational.heavyDutyFee,
    twoPersonFee: operational.twoPersonFee,
    tipAmount: operational.tipAmount,
    deliveryTimingType: operational.deliveryTimingType,
    scheduledPickupDate: operational.scheduledPickupDate,
    scheduledPickupWindow: operational.scheduledPickupWindow,
    vanguardEnabled: operational.vanguardEnabled,
    ...(completed ? {} : {
      senderName: operational.senderDetails.name,
      senderPhone: operational.senderDetails.phone,
      receiverName: operational.receiverDetails.name,
      receiverPhone: operational.receiverDetails.phone,
      collectionContactName: operational.collectionContact.name,
      collectionContactPhone: operational.collectionContact.phone,
      collectionContactDifferent: operational.collectionContact.differentFromSender,
    }),
  };
  return operational;
}

module.exports = {
  DEFAULT_MAX_DISPATCH_RADIUS_KM,
  accountEligibilityDecision,
  approvedServices,
  coordinate,
  dispatchEligibilityDecision,
  distanceKm,
  pickupCoordinate,
  presenceEligibilityDecision,
  riderCoordinate,
  riderAssignedJobProjection,
  riderOfferProjection,
  serviceEligibilityDecision,
  serviceName,
};
