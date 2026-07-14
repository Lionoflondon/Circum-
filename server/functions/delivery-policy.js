/* eslint-disable max-len, require-jsdoc */
const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const core = require("./delivery-policy-core");

function requireAuth(context) {
  if (!context.auth || !context.auth.uid) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in first.");
  }
  return context.auth.uid;
}

function text(value) {
  return `${value || ""}`.trim();
}

function assertSender(uid, delivery) {
  const sender = text(delivery.senderId || delivery.userId);
  if (!sender || sender !== uid) {
    throw new functions.https.HttpsError("permission-denied", "Only the sender can request this action.");
  }
}

function assertAssignedRider(uid, delivery) {
  const rider = text(delivery.riderId || delivery.assignedRiderId);
  if (!rider || rider !== uid) {
    throw new functions.https.HttpsError("permission-denied", "Only the assigned rider can request this action.");
  }
}

async function deliverySnapshot(transaction, deliveryId) {
  const ref = getFirestore().collection("deliveryRequests").doc(deliveryId);
  const snapshot = await transaction.get(ref);
  if (!snapshot.exists) {
    throw new functions.https.HttpsError("not-found", "Delivery not found.");
  }
  return {ref, delivery: {id: snapshot.id, ...snapshot.data()}};
}

function idempotencyRef(deliveryId, key) {
  return getFirestore()
      .collection("deliveryPolicyEvents")
      .doc(`${deliveryId}_${Buffer.from(key).toString("base64url")}`);
}

function policyPatch({state, event, evidenceId, extra = {}}) {
  return {
    state,
    deliveryStage: state,
    updatedAt: FieldValue.serverTimestamp(),
    policyEvidenceId: evidenceId,
    auditHistory: FieldValue.arrayUnion(event),
    ...extra,
  };
}

exports.requestSenderCancellation = functions.https.onCall(async (data, context) => {
  const uid = requireAuth(context);
  const deliveryId = text(data.deliveryId);
  const idempotencyKey = text(data.idempotencyKey || `${deliveryId}:sender_cancel:${uid}`);
  if (!deliveryId) throw new functions.https.HttpsError("invalid-argument", "deliveryId is required.");

  const db = getFirestore();
  const result = await db.runTransaction(async (transaction) => {
    const idemRef = idempotencyRef(deliveryId, idempotencyKey);
    const existing = await transaction.get(idemRef);
    if (existing.exists) return {...existing.data(), duplicate: true};

    const {ref, delivery} = await deliverySnapshot(transaction, deliveryId);
    assertSender(uid, delivery);
    const now = Date.now();
    const decision = core.cancellationDecision({
      delivery,
      state: delivery.state || delivery.status,
      serverNow: now,
    });
    if (!decision.canCancel) {
      return {success: false, decision};
    }

    const financial = decision.feeApplies ? core.financialAction({
      idempotencyKey,
      chargeType: "cancellation_fee",
      amount: decision.feeAmount,
      riderCompensation: decision.riderCompensation,
      platformRetainedAmount: decision.platformRetainedAmount,
      deliveryId,
      riderId: delivery.riderId,
      actorId: uid,
      actorType: "sender",
      reason: decision.cancellationType,
      serverNow: now,
    }) : null;
    const evidence = core.evidencePackage({
      deliveryId,
      actorId: uid,
      actorType: "sender",
      idempotencyKey,
      delivery,
      policyDecision: decision,
      serverNow: now,
    });
    const evidenceRef = db.collection("deliveryPolicyEvidence").doc();
    const event = {
      type: "sender_cancellation_requested",
      deliveryId,
      actorId: uid,
      actorType: "sender",
      decision,
      financial,
      evidenceId: evidenceRef.id,
      createdAt: now,
    };
    transaction.set(evidenceRef, evidence);
    transaction.set(idemRef, {success: true, decision, financial, evidenceId: evidenceRef.id, createdAt: now});
    transaction.update(ref, policyPatch({
      state: "cancelled_by_sender",
      event,
      evidenceId: evidenceRef.id,
      extra: {
        cancellationPolicy: decision,
        cancellationFinancial: financial,
        cancelledAt: FieldValue.serverTimestamp(),
        cancelledBy: uid,
      },
    }));
    return {success: true, decision, financial, evidenceId: evidenceRef.id};
  });
  return result;
});

exports.previewSenderCancellation = functions.https.onCall(async (data, context) => {
  const uid = requireAuth(context);
  const deliveryId = text(data.deliveryId || data.requestId);
  if (!deliveryId) throw new functions.https.HttpsError("invalid-argument", "deliveryId is required.");
  const db = getFirestore();
  const ref = db.collection("deliveryRequests").doc(deliveryId);
  const snapshot = await ref.get();
  if (!snapshot.exists) {
    throw new functions.https.HttpsError("not-found", "Delivery not found.");
  }
  const delivery = {id: snapshot.id, ...snapshot.data()};
  assertSender(uid, delivery);
  const decision = core.cancellationDecision({
    delivery,
    state: delivery.state || delivery.status,
    serverNow: Date.now(),
  });
  return {
    success: true,
    decision,
    cancellationFee: decision.feeAmount,
    feeAmount: decision.feeAmount,
    amount: decision.feeAmount,
    currency: "GBP",
    backendReason: decision.userFacingMessage || decision.adminFacingReason || "",
    reason: decision.cancellationType,
    amountToChargeOrRefund: decision.feeApplies ? decision.feeAmount : 0,
    canCancel: decision.canCancel,
  };
});

exports.recordRiderArrival = functions.https.onCall(async (data, context) => {
  const uid = requireAuth(context);
  const deliveryId = text(data.deliveryId);
  if (!deliveryId) throw new functions.https.HttpsError("invalid-argument", "deliveryId is required.");
  const phase = data.phase === "dropoff" ? "dropoff" : "pickup";
  const db = getFirestore();
  return db.runTransaction(async (transaction) => {
    const {ref, delivery} = await deliverySnapshot(transaction, deliveryId);
    assertAssignedRider(uid, delivery);
    const existingArrival = phase === "dropoff" ?
      delivery.dropoffArrivedAt : delivery.pickupArrivedAt;
    if (existingArrival && delivery.waiting && delivery.waiting.phase === phase) {
      return {
        success: true,
        duplicate: true,
        decision: {
          state: phase === "dropoff" ? "arrived_at_dropoff" : "arrived_at_pickup",
          waiting: delivery.waiting,
        },
      };
    }
    const now = Date.now();
    const decision = core.validateArrival({
      deliveryId,
      riderId: uid,
      delivery,
      phase,
      location: data.location || null,
      gpsAccuracyMeters: data.gpsAccuracyMeters,
      serverNow: now,
    });
    if (!decision.accepted) return {success: false, decision};
    const event = decision.auditEvent;
    const field = phase === "dropoff" ? "dropoffArrivedAt" : "pickupArrivedAt";
    transaction.update(ref, policyPatch({
      state: decision.state,
      event,
      evidenceId: delivery.policyEvidenceId || null,
      extra: {
        status: decision.state,
        deliveryStatus: decision.state,
        deliveryStage: decision.state,
        arrivedAt: FieldValue.serverTimestamp(),
        [field]: FieldValue.serverTimestamp(),
        arrivalLocation: decision.arrivalLocation || null,
        arrivalDistanceMeters: decision.distanceMeters || null,
        arrivalGpsAccuracyMeters: decision.gpsAccuracyMeters || null,
        waiting: decision.waiting,
        pendingNotification: {
          recipient: phase === "dropoff" ? "receiver" : "sender",
          message: phase === "dropoff" ? "Your rider is outside." : "Your rider is outside waiting for collection.",
          createdAt: now,
          triggeredByState: decision.state,
        },
      },
    }));
    return {success: true, decision};
  });
});

exports.recordArrivalZoneCheck = functions.https.onCall(async (data, context) => {
  const uid = requireAuth(context);
  const deliveryId = text(data.deliveryId);
  if (!deliveryId) throw new functions.https.HttpsError("invalid-argument", "deliveryId is required.");
  const phase = data.phase === "dropoff" ? "dropoff" : "pickup";
  const db = getFirestore();
  return db.runTransaction(async (transaction) => {
    const {ref, delivery} = await deliverySnapshot(transaction, deliveryId);
    assertAssignedRider(uid, delivery);
    const now = Date.now();
    const decision = core.geofenceReentryDecision({
      deliveryId,
      riderId: uid,
      delivery,
      phase,
      location: data.location || null,
      gpsAccuracyMeters: data.gpsAccuracyMeters,
      serverNow: now,
    });
    const extra = decision.waitingPaused ? {
      "waiting.paused": true,
      "waiting.pausedAt": now,
      "leftArrivalZoneAt": now,
      "lastKnownDistanceMeters": decision.lastKnownDistanceMeters || null,
      "arrivalGpsAccuracyMeters": decision.gpsAccuracyMeters || null,
    } : {
      "waiting.paused": false,
      "waiting.resumedAt": decision.reenteredArrivalZoneAt || now,
      "reenteredArrivalZoneAt": decision.reenteredArrivalZoneAt || null,
      "lastKnownDistanceMeters": decision.lastKnownDistanceMeters || null,
    };
    transaction.update(ref, {
      ...extra,
      updatedAt: FieldValue.serverTimestamp(),
      auditHistory: FieldValue.arrayUnion(decision.auditEvent),
    });
    return {success: true, decision};
  });
});

exports.recordCustomerArrivalResponse = functions.https.onCall(async (data, context) => {
  const uid = requireAuth(context);
  const deliveryId = text(data.deliveryId);
  if (!deliveryId) throw new functions.https.HttpsError("invalid-argument", "deliveryId is required.");
  const db = getFirestore();
  return db.runTransaction(async (transaction) => {
    const {ref, delivery} = await deliverySnapshot(transaction, deliveryId);
    assertSender(uid, delivery);
    const now = Date.now();
    const decision = core.customerResponseDecision({deliveryId, senderId: uid, delivery, response: data.response, serverNow: now});
    if (!decision.accepted) return {success: false, decision};
    transaction.update(ref, {
      customerArrivalResponses: FieldValue.arrayUnion(decision.auditEvent),
      customerWaitExtensions: FieldValue.increment(decision.extensionGranted ? 1 : 0),
      updatedAt: FieldValue.serverTimestamp(),
      auditHistory: FieldValue.arrayUnion(decision.auditEvent),
    });
    return {success: true, decision};
  });
});

exports.reportWaitingContext = functions.https.onCall(async (data, context) => {
  const uid = requireAuth(context);
  const deliveryId = text(data.deliveryId);
  if (!deliveryId) throw new functions.https.HttpsError("invalid-argument", "deliveryId is required.");
  const db = getFirestore();
  return db.runTransaction(async (transaction) => {
    const {ref, delivery} = await deliverySnapshot(transaction, deliveryId);
    assertAssignedRider(uid, delivery);
    const now = Date.now();
    const decision = core.waitingContextDecision({
      deliveryId,
      riderId: uid,
      type: data.type,
      note: data.note,
      serverNow: now,
    });
    transaction.update(ref, {
      waitingContextState: decision.state,
      requiresAdminReview: decision.requiresAdminReview,
      updatedAt: FieldValue.serverTimestamp(),
      auditHistory: FieldValue.arrayUnion(decision.auditEvent),
    });
    return {success: true, decision};
  });
});

exports.markRiderNoShow = functions.https.onCall(async (data, context) => {
  const uid = requireAuth(context);
  const deliveryId = text(data.deliveryId);
  const idempotencyKey = text(data.idempotencyKey || `${deliveryId}:no_show:${uid}`);
  if (!deliveryId) throw new functions.https.HttpsError("invalid-argument", "deliveryId is required.");
  const db = getFirestore();
  return db.runTransaction(async (transaction) => {
    const idemRef = idempotencyRef(deliveryId, idempotencyKey);
    const existing = await transaction.get(idemRef);
    if (existing.exists) return {...existing.data(), duplicate: true};
    const {ref, delivery} = await deliverySnapshot(transaction, deliveryId);
    assertAssignedRider(uid, delivery);
    const now = Date.now();
    const decision = core.noShowDecision({deliveryId, riderId: uid, delivery, serverNow: now});
    if (!decision.allowed) return {success: false, decision};
    const financial = core.financialAction({
      idempotencyKey,
      chargeType: "no_show_fee",
      amount: decision.feeAmount,
      riderCompensation: decision.riderCompensation,
      platformRetainedAmount: decision.platformRetainedAmount,
      deliveryId,
      riderId: uid,
      actorId: uid,
      actorType: "rider",
      reason: "sender_no_show_after_free_wait",
      startTime: decision.waitStartedAt,
      endTime: now,
      serverNow: now,
    });
    const evidence = core.evidencePackage({
      deliveryId,
      riderId: uid,
      actorId: uid,
      actorType: "rider",
      idempotencyKey,
      delivery,
      policyDecision: decision,
      serverNow: now,
    });
    const evidenceRef = db.collection("deliveryPolicyEvidence").doc();
    const event = {...decision.auditEvent, financial, evidenceId: evidenceRef.id};
    transaction.set(evidenceRef, evidence);
    transaction.set(idemRef, {success: true, decision, financial, evidenceId: evidenceRef.id, createdAt: now});
    transaction.update(ref, policyPatch({
      state: "sender_no_show_pickup",
      event,
      evidenceId: evidenceRef.id,
      extra: {
        noShowPolicy: decision,
        noShowFinancial: financial,
        noShowMarkedAt: FieldValue.serverTimestamp(),
      },
    }));
    return {success: true, decision, financial, evidenceId: evidenceRef.id};
  });
});

exports._core = core;
