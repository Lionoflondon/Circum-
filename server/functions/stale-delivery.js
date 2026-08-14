/* eslint-disable max-len, require-jsdoc */
const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const core = require("./stale-delivery-core");

function text(value) {
  return `${value || ""}`.trim();
}

function requireAdmin(context) {
  if (!context.auth || !context.auth.uid) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in first.");
  }
  const token = context.auth.token || {};
  if (token.admin !== true && token.superAdmin !== true && token.role !== "admin") {
    throw new functions.https.HttpsError("permission-denied", "Admin access required.");
  }
  return context.auth.uid;
}

function archivePatch({reason, actorUid, action = "admin_removed_stale"}) {
  return {
    status: action,
    deliveryStatus: action,
    flowStatus: action,
    matchingStatus: "blocked",
    dispatchStatus: "blocked",
    broadcastBlocked: true,
    broadcastBlockReason: action,
    active: false,
    archived: true,
    staleArchived: true,
    staleState: action,
    removedFromActiveQueues: true,
    staleCleanupReason: reason,
    archivedAt: FieldValue.serverTimestamp(),
    archivedByAdminId: actorUid,
    updatedAt: FieldValue.serverTimestamp(),
  };
}

async function releaseRiderLock(batch, db, {riderId, deliveryId, reason, actorUid}) {
  if (!riderId) return;
  const presenceRef = db.collection("riderPresence").doc(riderId);
  const presence = await presenceRef.get();
  if (!presence.exists) return;
  const data = presence.data();
  const referenced = text(data.activeDeliveryId || data.currentDeliveryId);
  if (referenced !== deliveryId) return;
  batch.set(presenceRef, {
    activeDeliveryId: FieldValue.delete(),
    currentDeliveryId: FieldValue.delete(),
    busy: false,
    availabilityStatus: data.isOnline === true ? "available" : "offline",
    updatedAt: FieldValue.serverTimestamp(),
    source: "staleDeliveryReconciliation",
  }, {merge: true});
  batch.set(db.collection("riderOperationalAudit").doc(), {
    riderId,
    deliveryId,
    action: "stale_active_delivery_reference_repaired",
    reason,
    actorUid,
    createdAt: FieldValue.serverTimestamp(),
  });
}

async function referencedPresenceDocs(db) {
  const [activeSnapshot, currentSnapshot] = await Promise.all([
    db.collection("riderPresence").where("activeDeliveryId", ">", "").limit(500).get(),
    db.collection("riderPresence").where("currentDeliveryId", ">", "").limit(500).get(),
  ]);
  const docs = new Map();
  for (const doc of [...activeSnapshot.docs, ...currentSnapshot.docs]) {
    docs.set(doc.id, doc);
  }
  return [...docs.values()];
}

exports.resolveStaleDeliveryLock = functions.runWith({enforceAppCheck: true}).https.onCall(async (data, context) => {
  const actorUid = requireAdmin(context);
  const deliveryId = text(data && data.deliveryId);
  const reason = text(data && data.reason);
  const requestedAction = text(data && data.action) || "admin_removed_stale";
  const allowedActions = new Set(["admin_removed_stale", "archived_stale", "cancelled_admin"]);
  if (!deliveryId || reason.length < 4 || !allowedActions.has(requestedAction)) {
    throw new functions.https.HttpsError("invalid-argument", "Delivery, action and a clear reason are required.");
  }
  const db = getFirestore();
  const deliveryRef = db.collection("deliveryRequests").doc(deliveryId);
  const deliveryDoc = await deliveryRef.get();
  if (!deliveryDoc.exists) throw new functions.https.HttpsError("not-found", "Delivery not found.");
  const delivery = deliveryDoc.data();
  if (core.hasPickupEvidence(delivery) || core.PICKED_UP.has(core.statusOf(delivery))) {
    throw new functions.https.HttpsError("failed-precondition", "Collected deliveries require operational review and cannot be cleared here.");
  }
  const riderId = text(delivery.riderId || delivery.assignedRiderId);
  const batch = db.batch();
  batch.set(deliveryRef, archivePatch({reason, actorUid, action: requestedAction}), {merge: true});
  await releaseRiderLock(batch, db, {riderId, deliveryId, reason, actorUid});
  batch.set(db.collection("adminAuditLogs").doc(), {
    action: "stale_delivery_resolved",
    actionType: "stale_delivery_resolved",
    recordType: "deliveryRequests",
    recordId: deliveryId,
    previousStatus: core.statusOf(delivery),
    newStatus: requestedAction,
    reason,
    actorUid,
    createdAt: FieldValue.serverTimestamp(),
  });
  batch.set(db.collection("staleDeliveryQueue").doc(deliveryId), {
    deliveryId,
    riderId,
    status: "resolved",
    resolution: requestedAction,
    reason,
    resolvedBy: actorUid,
    resolvedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  await batch.commit();
  return {success: true, deliveryId, riderId, status: requestedAction, riderLockReleased: Boolean(riderId)};
});

exports.reconcileStaleDeliveryLocks = functions.pubsub
    .schedule("every 15 minutes")
    .timeZone("Europe/London")
    .onRun(async () => {
      const db = getFirestore();
      const presenceDocs = await referencedPresenceDocs(db);
      let repaired = 0;
      let queued = 0;
      for (const presenceDoc of presenceDocs) {
        const presence = presenceDoc.data();
        const deliveryId = text(presence.activeDeliveryId || presence.currentDeliveryId);
        if (!deliveryId) continue;
        const deliveryDoc = await db.collection("deliveryRequests").doc(deliveryId).get();
        const trackingDoc = deliveryDoc.exists ?
          await deliveryDoc.ref.collection("tracking").doc("liveLocation").get() : null;
        const delivery = deliveryDoc.exists ? {
          ...deliveryDoc.data(),
          _lastTrackingAt: trackingDoc && trackingDoc.exists ? trackingDoc.data().updatedAt : null,
        } : null;
        const decision = core.evaluateDeliveryLock(delivery, {exists: deliveryDoc.exists});
        if (!decision.repair && !decision.review) continue;
        if (decision.review) {
          await db.collection("staleDeliveryQueue").doc(deliveryId).set({
            deliveryId,
            riderId: presenceDoc.id,
            deliveryStatus: core.statusOf(delivery),
            reason: decision.reason,
            paymentStatus: text(delivery.paymentStatus),
            pickupOccurred: core.hasPickupEvidence(delivery),
            status: "needs_review",
            firstDetectedAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
          }, {merge: true});
          queued += 1;
          continue;
        }
        const batch = db.batch();
        const riderId = presenceDoc.id;
        await releaseRiderLock(batch, db, {
          riderId,
          deliveryId,
          reason: decision.reason,
          actorUid: "system",
        });
        batch.set(db.collection("staleDeliveryQueue").doc(deliveryId), {
          deliveryId,
          riderId,
          deliveryStatus: delivery ? core.statusOf(delivery) : "missing",
          reason: decision.reason,
          paymentStatus: delivery ? text(delivery.paymentStatus) : "",
          pickupOccurred: delivery ? core.hasPickupEvidence(delivery) : false,
          status: decision.archive ? "needs_review" : "reference_repaired",
          firstDetectedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
        await batch.commit();
        repaired += 1;
        if (decision.archive) queued += 1;
      }
      return {repaired, queued};
    });

module.exports.archivePatch = archivePatch;
module.exports.releaseRiderLock = releaseRiderLock;
