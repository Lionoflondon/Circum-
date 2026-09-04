/* eslint-disable max-len, require-jsdoc */

const DEFAULT_POLICY = Object.freeze({
  defaultArrivalRadiusMeters: 40,
  gpsToleranceMeters: 15,
  freeWaitMinutes: 3,
  maximumOperationalWaitMinutes: 25,
  acceptedCancellationFee: 3,
  acceptedRiderCompensation: 2,
  acceptedPlatformRetained: 1,
  arrivedFreeWaitCancellationFee: 5,
  arrivedFreeWaitRiderCompensation: 3,
  arrivedFreeWaitPlatformRetained: 2,
  lateNoShowFee: 7,
  lateNoShowRiderCompensation: 4,
  lateNoShowPlatformRetained: 3,
  customerExtensionMinutes: 2,
  maxCustomerExtensions: 1,
});

const ACTIVE_PRE_COLLECTION = new Set([
  "accepted",
  "rider_assigned",
  "navigating_to_pickup",
  "en_route_to_pickup",
]);

const ARRIVED_PICKUP = new Set([
  "arrived_at_pickup",
  "waiting_for_collection",
  "waiting",
]);

const IN_PROGRESS_AFTER_COLLECTION = new Set([
  "pickup_verification",
  "pickup_verified",
  "collected",
  "navigating_to_dropoff",
  "arrived_at_dropoff",
  "pin_required",
]);

const TERMINAL = new Set(["delivered"]);

function policy(overrides = {}) {
  return Object.freeze({...DEFAULT_POLICY, ...overrides});
}

function normalizeState(value) {
  return `${value || ""}`.trim().toLowerCase().replace(/[-\s]+/g, "_");
}

function money(value) {
  return Math.round((Number(value) || 0) * 100) / 100;
}

function minutesToMs(minutes) {
  return Math.round((Number(minutes) || 0) * 60 * 1000);
}

function toMillis(value) {
  if (value == null) return null;
  if (typeof value === "number") return value;
  if (value instanceof Date) return value.getTime();
  if (typeof value.toMillis === "function") return value.toMillis();
  if (typeof value.seconds === "number") return value.seconds * 1000;
  const parsed = Date.parse(value);
  return Number.isNaN(parsed) ? null : parsed;
}

function serverNow(input = {}) {
  const now = Number(input.serverNow);
  if (!Number.isFinite(now)) {
    throw new Error("serverNow is required for policy decisions.");
  }
  return now;
}

function freeWaitExpired(delivery = {}, serverTime, config = policy()) {
  const arrivedAt = toMillis(delivery.arrivedAt || delivery.pickupArrivedAt || delivery.dropoffArrivedAt);
  if (!arrivedAt) return false;
  return serverTime >= arrivedAt + minutesToMs(config.freeWaitMinutes);
}

function cancellationDecision(input = {}) {
  const config = policy(input.policy);
  const state = normalizeState(input.state || input.delivery && input.delivery.state);
  const now = serverNow(input);
  const expired = freeWaitExpired(input.delivery || {}, now, config);
  const base = {
    canCancel: false,
    cancellationType: "not_allowed",
    feeApplies: false,
    feeAmount: 0,
    riderCompensation: 0,
    platformRetainedAmount: 0,
    requiresAdminReview: false,
    freeWaitExpired: expired,
    waitingChargeApplies: false,
    noShowAvailable: false,
    userFacingMessage: "",
    riderFacingMessage: "",
    adminFacingReason: "",
    allowedActions: [],
  };

  if (["finding_rider", "pending", "unmatched", "requested", "broadcasting", "available", "awaiting_rider"].includes(state)) {
    return {
      ...base,
      canCancel: true,
      cancellationType: "before_acceptance",
      userFacingMessage: "You can cancel this delivery at no charge.",
      adminFacingReason: "Sender cancelled before rider acceptance.",
      allowedActions: ["cancel"],
    };
  }

  if (ACTIVE_PRE_COLLECTION.has(state)) {
    return {
      ...base,
      canCancel: true,
      cancellationType: "after_acceptance",
      feeApplies: true,
      feeAmount: config.acceptedCancellationFee,
      riderCompensation: config.acceptedRiderCompensation,
      platformRetainedAmount: config.acceptedPlatformRetained,
      userFacingMessage: "Your rider has already accepted this job. Cancelling now incurs a £3 cancellation fee.",
      riderFacingMessage: "Delivery cancelled after acceptance. £2 compensation added.",
      adminFacingReason: "Sender cancelled after rider accepted but before arrival.",
      allowedActions: ["cancel_with_fee"],
    };
  }

  if (ARRIVED_PICKUP.has(state)) {
    const late = expired;
    return {
      ...base,
      canCancel: true,
      cancellationType: late ? "late_no_show" : "arrived_free_wait",
      feeApplies: true,
      feeAmount: late ? config.lateNoShowFee : config.arrivedFreeWaitCancellationFee,
      riderCompensation: late ? config.lateNoShowRiderCompensation : config.arrivedFreeWaitRiderCompensation,
      platformRetainedAmount: late ? config.lateNoShowPlatformRetained : config.arrivedFreeWaitPlatformRetained,
      waitingChargeApplies: late,
      noShowAvailable: late,
      userFacingMessage: "Your rider is already outside. Cancelling now may incur a late cancellation/no-show fee.",
      riderFacingMessage: late ? "Late cancellation/no-show recorded. Compensation may apply." : "Delivery cancelled while waiting. Compensation may apply.",
      adminFacingReason: late ? "Sender cancelled after free wait expired." : "Sender cancelled during pickup free wait.",
      allowedActions: late ? ["cancel_late", "mark_no_show"] : ["cancel_with_arrival_fee"],
    };
  }

  if (IN_PROGRESS_AFTER_COLLECTION.has(state)) {
    return {
      ...base,
      requiresAdminReview: true,
      userFacingMessage: "This delivery is already in progress. Contact support if there is a problem.",
      adminFacingReason: "Sender self-cancellation blocked after collection flow started.",
      allowedActions: ["contact_support", "admin_review"],
    };
  }

  if (TERMINAL.has(state)) {
    return {
      ...base,
      userFacingMessage: "This delivery has been completed.",
      adminFacingReason: "Cancellation disabled after delivery completion.",
      allowedActions: ["support", "refund_review", "dispute"],
    };
  }

  if (state === "issue_reported") {
    return {
      ...base,
      requiresAdminReview: true,
      userFacingMessage: "Support is reviewing this delivery.",
      adminFacingReason: "Issue reported; outcome controlled by support/admin policy.",
      allowedActions: ["support_review"],
    };
  }

  return {
    ...base,
    requiresAdminReview: true,
    userFacingMessage: "Contact support if there is a problem with this delivery.",
    adminFacingReason: `Unhandled cancellation state: ${state || "unknown"}.`,
    allowedActions: ["support_review"],
  };
}

function radians(value) {
  return value * Math.PI / 180;
}

function distanceMeters(a, b) {
  if (!a || !b) return null;
  const lat1 = Number(a.lat);
  const lon1 = Number(a.lng);
  const lat2 = Number(b.lat);
  const lon2 = Number(b.lng);
  if (![lat1, lon1, lat2, lon2].every(Number.isFinite)) return null;
  const earth = 6371000;
  const dLat = radians(lat2 - lat1);
  const dLon = radians(lon2 - lon1);
  const h = Math.sin(dLat / 2) ** 2 +
    Math.cos(radians(lat1)) * Math.cos(radians(lat2)) *
    Math.sin(dLon / 2) ** 2;
  return 2 * earth * Math.asin(Math.sqrt(h));
}

function validateArrival(input = {}) {
  const config = policy(input.policy);
  const now = serverNow(input);
  const delivery = input.delivery || {};
  const riderId = `${input.riderId || ""}`.trim();
  const assigned = `${delivery.riderId || delivery.assignedRiderId || ""}`.trim();
  const phase = input.phase === "dropoff" ? "dropoff" : "pickup";
  const location = input.location || null;
  const recordedAt = toMillis(location && location.clientRecordedAt);
  const target = input.target || (phase === "dropoff" ? delivery.dropoffLocation : delivery.pickupLocation);
  const existingArrival = phase === "dropoff" ? delivery.dropoffArrivedAt : delivery.pickupArrivedAt;
  const distance = distanceMeters(location, target);
  const accuracy = Number(input.gpsAccuracyMeters);
  const tolerance = Number.isFinite(accuracy) ? Math.max(config.gpsToleranceMeters, accuracy) : config.gpsToleranceMeters;
  const allowedDistance = config.defaultArrivalRadiusMeters + tolerance;

  if (assigned && assigned !== riderId) {
    return {accepted: false, flagged: true, reason: "assigned_rider_required", auditEvent: auditEvent("arrival_rejected", input, now, {phase})};
  }
  if (existingArrival) {
    return {accepted: false, duplicate: true, reason: "arrival_already_recorded", auditEvent: auditEvent("arrival_duplicate", input, now, {phase})};
  }
  if (!location || location.mocked === true || !recordedAt || now - recordedAt > 2 * 60 * 1000 || recordedAt > now + 30 * 1000) {
    return {
      accepted: false,
      flagged: true,
      reason: location && location.mocked === true ? "mocked_location" : "fresh_location_required",
      auditEvent: auditEvent("arrival_rejected_untrusted_location", input, now, {phase}),
    };
  }
  if (!Number.isFinite(accuracy) || accuracy <= 0 || accuracy > 100) {
    return {accepted: false, flagged: true, reason: "accurate_location_required", auditEvent: auditEvent("arrival_rejected_inaccurate_location", input, now, {phase})};
  }
  if (distance == null) {
    return {accepted: false, flagged: true, reason: "valid_location_required", auditEvent: auditEvent("arrival_rejected_gps_missing", input, now, {phase})};
  }
  if (distance > allowedDistance) {
    return {
      accepted: false,
      flagged: true,
      reason: "outside_arrival_radius",
      distanceMeters: Math.round(distance),
      allowedDistanceMeters: Math.round(allowedDistance),
      auditEvent: auditEvent("arrival_rejected_outside_radius", input, now, {phase, distanceMeters: Math.round(distance)}),
    };
  }
  return {
    accepted: true,
    flagged: false,
    reason: "arrival_verified",
    state: phase === "dropoff" ? "arrived_at_dropoff" : "arrived_at_pickup",
    arrivedAt: now,
    arrivalLocation: location,
    distanceMeters: Math.round(distance),
    gpsAccuracyMeters: Number.isFinite(accuracy) ? accuracy : null,
    waiting: waitingState({deliveryId: input.deliveryId, riderId, phase, now, config}),
    auditEvent: auditEvent("arrival_verified", input, now, {phase, distanceMeters: Math.round(distance)}),
  };
}

function waitingState({deliveryId, riderId, phase, now, config}) {
  return {
    active: true,
    paused: false,
    deliveryId,
    riderId,
    phase,
    freeWaitMinutes: config.freeWaitMinutes,
    maximumOperationalWaitMinutes: config.maximumOperationalWaitMinutes,
    startedAt: now,
    freeWaitEndsAt: now + minutesToMs(config.freeWaitMinutes),
    maximumWaitEndsAt: now + minutesToMs(config.maximumOperationalWaitMinutes),
    noShowAvailableAt: now + minutesToMs(config.freeWaitMinutes),
    noShowFeeAmount: config.lateNoShowFee,
    noShowRiderCompensation: config.lateNoShowRiderCompensation,
    noShowPlatformRetainedAmount: config.lateNoShowPlatformRetained,
    currency: "GBP",
    billablePausedMs: 0,
  };
}

function geofenceReentryDecision(input = {}) {
  const config = policy(input.policy);
  const now = serverNow(input);
  const delivery = input.delivery || {};
  const phase = input.phase === "dropoff" ? "dropoff" : "pickup";
  const location = input.location || null;
  const target = input.target || (phase === "dropoff" ? delivery.dropoffLocation : delivery.pickupLocation);
  const distance = distanceMeters(location, target);
  const accuracy = Number(input.gpsAccuracyMeters);
  const tolerance = Number.isFinite(accuracy) ? Math.max(config.gpsToleranceMeters, accuracy) : config.gpsToleranceMeters;
  const outside = distance == null ? false : distance > config.defaultArrivalRadiusMeters + tolerance;
  if (outside) {
    return {
      waitingPaused: true,
      leftArrivalZoneAt: now,
      lastKnownDistanceMeters: Math.round(distance),
      gpsAccuracyMeters: Number.isFinite(accuracy) ? accuracy : null,
      riderMessage: phase === "dropoff" ? "Return to the drop-off location to continue waiting." : "Return to the pickup location to continue waiting.",
      auditEvent: auditEvent("left_arrival_zone", input, now, {phase, distanceMeters: Math.round(distance)}),
    };
  }
  if (delivery.waiting && delivery.waiting.paused) {
    return {
      waitingPaused: false,
      reenteredArrivalZoneAt: now,
      lastKnownDistanceMeters: distance == null ? null : Math.round(distance),
      gpsAccuracyMeters: Number.isFinite(accuracy) ? accuracy : null,
      riderMessage: "Waiting resumed.",
      auditEvent: auditEvent("reentered_arrival_zone", input, now, {phase}),
    };
  }
  return {waitingPaused: false, auditEvent: auditEvent("arrival_zone_checked", input, now, {phase})};
}

function customerResponseDecision(input = {}) {
  const config = policy(input.policy);
  const now = serverNow(input);
  const response = `${input.response || ""}`
      .trim()
      .toLowerCase()
      .replace(/[^\w\s-]+/g, "")
      .replace(/[\s-]+/g, "_");
  const usedExtensions = Number(input.delivery && input.delivery.customerWaitExtensions || 0);
  const allowed = ["im_coming", "need_2_more_minutes", "cant_come_out"];
  if (!allowed.includes(response)) {
    return {accepted: false, reason: "unsupported_response"};
  }
  const extensionGranted = response === "need_2_more_minutes" && usedExtensions < config.maxCustomerExtensions;
  return {
    accepted: true,
    response,
    extensionGranted,
    extensionMinutes: extensionGranted ? config.customerExtensionMinutes : 0,
    escalationPaused: response === "im_coming" || extensionGranted,
    supportPathRequired: response === "cant_come_out",
    auditEvent: auditEvent("customer_arrival_response", input, now, {response, extensionGranted}),
  };
}

function waitingContextDecision(input = {}) {
  const now = serverNow(input);
  const type = input.type === "unsafe_location_reported" ? "unsafe_location_reported" : "waiting_for_building_access";
  return {
    state: type,
    requiresAdminReview: type === "unsafe_location_reported",
    noShowPenaltyAllowed: false,
    autoCancelAllowed: false,
    escalationPaused: true,
    auditEvent: auditEvent(type, input, now, {note: input.note || ""}),
  };
}

function noShowDecision(input = {}) {
  const config = policy(input.policy);
  const delivery = input.delivery || {};
  const now = serverNow(input);
  const arrivedAt = toMillis(delivery.arrivedAt || delivery.pickupArrivedAt || delivery.dropoffArrivedAt);
  const state = normalizeState(delivery.state);
  const active = !["delivered", "cancelled", "sender_no_show_pickup"].includes(state);
  const expired = arrivedAt != null && now >= arrivedAt + minutesToMs(config.freeWaitMinutes);
  if (!arrivedAt || !active || !expired) {
    return {
      allowed: false,
      reason: !arrivedAt ? "valid_arrival_required" : !active ? "delivery_not_active" : "free_wait_active",
      freeWaitExpired: expired,
      auditEvent: auditEvent("no_show_rejected", input, now, {reason: "threshold_not_met"}),
    };
  }
  return {
    allowed: true,
    feeAmount: config.lateNoShowFee,
    riderCompensation: config.lateNoShowRiderCompensation,
    platformRetainedAmount: config.lateNoShowPlatformRetained,
    waitStartedAt: arrivedAt,
    waitExpiredAt: arrivedAt + minutesToMs(config.freeWaitMinutes),
    noShowMarkedAt: now,
    policyDecision: "late_no_show",
    auditEvent: auditEvent("no_show_marked", input, now, {waitStartedAt: arrivedAt}),
  };
}

function financialAction(input = {}) {
  const existing = input.existingByIdempotencyKey || {};
  const key = `${input.idempotencyKey || ""}`.trim();
  if (!key) throw new Error("idempotencyKey is required.");
  if (existing[key]) return {...existing[key], duplicate: true};
  const now = serverNow(input);
  const amount = money(input.amount);
  const riderCompensation = money(input.riderCompensation);
  const platformRetainedAmount = money(input.platformRetainedAmount);
  return {
    duplicate: false,
    idempotencyKey: key,
    chargeId: input.chargeId || `charge_${key}`,
    chargeType: input.chargeType,
    amount,
    riderCompensation,
    platformRetainedAmount,
    startTime: input.startTime || now,
    endTime: input.endTime || now,
    reason: input.reason,
    deliveryId: input.deliveryId,
    riderId: input.riderId,
    actorId: input.actorId,
    actorType: input.actorType,
    createdAt: now,
    auditEvent: auditEvent(`${input.chargeType || "financial"}_recorded`, input, now, {idempotencyKey: key}),
  };
}

function fraudSignals(input = {}) {
  const stats = input.stats || {};
  const signals = [];
  if (Number(stats.riderNoShowCount) >= 5) signals.push("rider_high_no_show_count");
  if (Number(stats.riderWaitingCompensationCount) >= 5) signals.push("rider_high_waiting_compensation_count");
  if (Number(stats.senderNoShowCount) >= 5) signals.push("sender_repeated_no_show");
  if (Number(stats.senderLateCancellationCount) >= 5) signals.push("sender_repeated_late_cancellation");
  if (Number(stats.arrivalNearBoundaryCount) >= 3) signals.push("arrival_near_radius_boundary");
  if (Number(stats.failedGpsValidationCount) >= 3) signals.push("repeated_failed_gps_validation");
  return signals.map((type) => ({type, severity: "review", automaticPenalty: false}));
}

function evidencePackage(input = {}) {
  const now = serverNow(input);
  const delivery = input.delivery || {};
  const decision = input.policyDecision || {};
  return {
    deliveryId: input.deliveryId || delivery.id,
    riderId: input.riderId || delivery.riderId,
    senderId: input.senderId || delivery.senderId || delivery.userId,
    receiverId: input.receiverId || delivery.receiverId,
    currentDeliveryState: normalizeState(delivery.state),
    previousState: input.previousState || delivery.previousState || null,
    pickup: delivery.pickup || delivery.pickupDetails || null,
    dropoff: delivery.dropoff || delivery.dropoffDetails || null,
    arrivalLocation: input.arrivalLocation || delivery.arrivalLocation || null,
    gpsAccuracyMeters: input.gpsAccuracyMeters || null,
    arrivalTimestamp: toMillis(delivery.arrivedAt || delivery.pickupArrivedAt || delivery.dropoffArrivedAt),
    leftArrivalZoneAt: delivery.leftArrivalZoneAt || null,
    reenteredArrivalZoneAt: delivery.reenteredArrivalZoneAt || null,
    waitStartedAt: delivery.waiting && delivery.waiting.startedAt || null,
    waitPausedAt: delivery.waiting && delivery.waiting.pausedAt || null,
    waitResumedAt: delivery.waiting && delivery.waiting.resumedAt || null,
    waitEndedAt: input.waitEndedAt || null,
    totalBillableWaitMs: input.totalBillableWaitMs || 0,
    freeWaitExpiry: delivery.waiting && delivery.waiting.freeWaitEndsAt || null,
    notificationsSent: input.notificationsSent || delivery.notificationsSent || [],
    customerResponses: input.customerResponses || delivery.customerArrivalResponses || [],
    contactAttempts: input.contactAttempts || delivery.contactAttempts || [],
    buildingAccessReports: input.buildingAccessReports || delivery.buildingAccessReports || [],
    unsafeLocationReports: input.unsafeLocationReports || delivery.unsafeLocationReports || [],
    photos: input.photos || delivery.photos || [],
    verificationEvents: input.verificationEvents || delivery.verificationEvents || [],
    cancellationReason: input.cancellationReason || delivery.cancellationReason || null,
    policyDecision: decision,
    feeAmount: decision.feeAmount || input.feeAmount || 0,
    riderCompensation: decision.riderCompensation || input.riderCompensation || 0,
    platformRetainedAmount: decision.platformRetainedAmount || input.platformRetainedAmount || 0,
    idempotencyKey: input.idempotencyKey || null,
    actorId: input.actorId,
    actorType: input.actorType,
    createdAt: now,
    updatedAt: now,
  };
}

function auditEvent(type, input, now, extra = {}) {
  return {
    type,
    deliveryId: input.deliveryId || input.delivery && input.delivery.id,
    riderId: input.riderId || input.delivery && input.delivery.riderId,
    actorId: input.actorId || input.riderId || input.senderId,
    actorType: input.actorType || "system",
    createdAt: now,
    ...extra,
  };
}

module.exports = {
  DEFAULT_POLICY,
  ACTIVE_PRE_COLLECTION,
  ARRIVED_PICKUP,
  IN_PROGRESS_AFTER_COLLECTION,
  cancellationDecision,
  customerResponseDecision,
  distanceMeters,
  evidencePackage,
  financialAction,
  fraudSignals,
  freeWaitExpired,
  geofenceReentryDecision,
  noShowDecision,
  normalizeState,
  policy,
  validateArrival,
  waitingContextDecision,
};
