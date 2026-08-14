/* eslint-disable max-len, require-jsdoc */
const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {requireAdmin} = require("./admin-auth");
const {assertFounder} = require("./founder-authority");

const archiveStatuses = new Set([
  "archived_stale",
  "archived_expired",
  "admin_removed_stale",
  "cancelled_admin",
  "stale_blocked",
]);

const protectedStatuses = new Set([
  "accepted",
  "rider_assigned",
  "en_route_to_pickup",
  "arrived_at_pickup",
  "rider_arrived_pickup",
  "collected",
  "picked_up",
  "in_transit",
  "arriving",
  "delivered",
  "completed",
  "under_review",
  "disputed",
  "dispute",
  "payment_complete",
  "paid",
]);

const founderPurgeOpenStatuses = new Set([
  "searching",
  "requested",
  "pending",
  "broadcast",
  "broadcasted",
  "finding_rider",
  "awaiting_rider",
]);

const transientDeliveryCollections = [
  "dispatchInspections",
  "irisPrivate",
  "staleDeliveryQueue",
  "dispatchQueue",
  "matchmakingQueue",
  "dispatchReservations",
  "deliveryOffers",
  "riderOffers",
];

const offerCollections = new Set(["deliveryOffers", "riderOffers"]);
const reservationCollections = new Set(["dispatchReservations"]);
const queueCollections = new Set(["staleDeliveryQueue", "dispatchQueue", "matchmakingQueue"]);
const irisTemporaryCollections = new Set(["dispatchInspections", "irisPrivate"]);

function normalize(value) {
  return `${value || ""}`.trim().toLowerCase();
}

function readDate(value) {
  if (!value) return null;
  if (value instanceof Date) return value;
  if (typeof value.toDate === "function") return value.toDate();
  if (typeof value === "string") {
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? null : date;
  }
  return null;
}

function readMillis(value) {
  const date = readDate(value);
  if (date) return date.getTime();
  if (typeof value === "number") return value;
  if (value && typeof value.toMillis === "function") return value.toMillis();
  if (value && typeof value.seconds === "number") return value.seconds * 1000;
  return null;
}

function nonEmpty(value) {
  const text = `${value || ""}`.trim();
  return text.length > 0 && text !== "null" && text !== "undefined";
}

function missingCanonicalFields(delivery) {
  const missing = [];
  const requireAny = (label, values) => {
    if (!values.some(nonEmpty)) missing.push(label);
  };
  requireAny("sender id", [
    delivery.senderId,
    delivery.userId,
    delivery.bookedByUserId,
    delivery.authenticatedUserUid,
  ]);
  requireAny("sender email", [
    delivery.senderEmail,
    delivery.senderEmailLower,
    delivery.email,
    delivery.senderDetails && delivery.senderDetails.email,
  ]);
  requireAny("pickup address", [
    delivery.pickupAddress,
    delivery.pickup,
    delivery.pickupAddressCanonical && delivery.pickupAddressCanonical.formattedAddress,
  ]);
  requireAny("drop-off address", [
    delivery.dropoffAddress,
    delivery.dropOffAddress,
    delivery.dropoffAddressCanonical && delivery.dropoffAddressCanonical.formattedAddress,
  ]);
  requireAny("recipient", [
    delivery.receiverName,
    delivery.recipientName,
    delivery.receiverDetails && delivery.receiverDetails.name,
  ]);
  requireAny("payment status", [delivery.paymentStatus]);
  requireAny("tracking URL", [delivery.trackingUrl]);
  return [...new Set(missing)];
}

function isArchiveRecord(delivery) {
  return delivery.archived === true ||
    delivery.adminRemovedStale === true ||
    archiveStatuses.has(normalize(delivery.status)) ||
    archiveStatuses.has(normalize(delivery.deliveryStatus)) ||
    archiveStatuses.has(normalize(delivery.flowStatus));
}

function canAutoArchiveExpired(delivery, now = new Date()) {
  if (isArchiveRecord(delivery)) return false;
  const statuses = [
    delivery.status,
    delivery.deliveryStatus,
    delivery.flowStatus,
    delivery.paymentStatus,
    delivery.matchingStatus,
    delivery.dispatchStatus,
  ].map(normalize);
  if (statuses.some((status) => protectedStatuses.has(status))) return false;
  if (delivery.disputeOpen === true || delivery.underReview === true || delivery.paymentInvestigation === true) return false;
  if (normalize(delivery.paymentStatus) === "paid" || delivery.paid === true) return false;
  const createdAt = readDate(delivery.createdAt) || readDate(delivery.requestedAt) || readDate(delivery.updatedAt);
  if (!createdAt) return false;
  if (now.getTime() - createdAt.getTime() < 24 * 60 * 60 * 1000) return false;
  const missing = missingCanonicalFields(delivery);
  const staleStatus = ["requested", "pending", "finding_rider", "recoverable_incomplete"].includes(normalize(delivery.status)) ||
    normalize(delivery.flowStatus) === "recoverable_incomplete" ||
    normalize(delivery.matchingStatus) === "available";
  return missing.length > 0 || staleStatus || delivery.stale === true || delivery.manuallyMarkedStale === true;
}

function isFounderTestDelivery(delivery = {}) {
  return delivery.founderTest === true ||
    delivery.internalTest === true ||
    delivery.testDelivery === true ||
    delivery.isTest === true ||
    normalize(delivery.testMode) === "founder" ||
    normalize(delivery.deliveryMode) === "founder_test" ||
    normalize(delivery.source) === "founder_e2e";
}

function hasAssignedRider(delivery = {}) {
  return nonEmpty(delivery.riderId) ||
    nonEmpty(delivery.assignedRiderId) ||
    nonEmpty(delivery.acceptedByRiderId) ||
    nonEmpty(delivery.reservedByRiderId);
}

function hasActiveWorkflow(delivery = {}) {
  return delivery.disputeOpen === true ||
    delivery.underReview === true ||
    delivery.paymentInvestigation === true ||
    delivery.cancellationPending === true ||
    delivery.cancelRequested === true ||
    delivery.refundPending === true ||
    delivery.assignmentLocked === true ||
    delivery.reservationLocked === true ||
    delivery.liveAssignmentLock === true ||
    nonEmpty(delivery.assignmentLockId) ||
    nonEmpty(delivery.reservationId);
}

function founderPurgeAgeExpired(delivery = {}, now = new Date(), expirationMs = 24 * 60 * 60 * 1000) {
  const explicitExpiry = readMillis(delivery.offerExpiresAt || delivery.dispatchExpiresAt ||
    delivery.expiresAt || delivery.matchingExpiresAt);
  if (explicitExpiry && explicitExpiry <= now.getTime()) return true;
  const created = readMillis(delivery.createdAt || delivery.requestedAt || delivery.updatedAt);
  return Boolean(created && now.getTime() - created >= expirationMs);
}

function canFounderPurgeDelivery(delivery, now = new Date(), expirationMs = 24 * 60 * 60 * 1000) {
  if (!delivery || isArchiveRecord(delivery)) return false;
  const statuses = [
    delivery.status,
    delivery.deliveryStatus,
    delivery.flowStatus,
    delivery.matchingStatus,
    delivery.dispatchStatus,
  ].map(normalize);
  if (statuses.some((status) => protectedStatuses.has(status))) return false;
  if (!statuses.some((status) => founderPurgeOpenStatuses.has(status))) return false;
  if (hasAssignedRider(delivery)) return false;
  if (hasActiveWorkflow(delivery)) return false;
  return isFounderTestDelivery(delivery) || founderPurgeAgeExpired(delivery, now, expirationMs);
}

function pipelineHealthScore(report) {
  const staleTotal = report.staleSearchingDeliveries +
    report.expiredRiderOffers +
    report.staleReservations +
    report.staleQueueEntries +
    report.orphanedIrisSessions;
  return Math.max(0, Math.min(100, 100 - staleTotal * 5));
}

async function scanTransientHealth(db, collection, now, expirationMs, limit) {
  const snapshot = await db.collection(collection).limit(limit).get().catch(() => null);
  const summary = {active: 0, stale: 0, refs: []};
  if (!snapshot) return summary;
  snapshot.docs.forEach((doc) => {
    const data = doc.data() || {};
    const active = data.active === true || ["active", "pending", "offered", "reserved", "queued"].includes(normalize(data.status));
    const expiry = readMillis(data.expiresAt || data.offerExpiresAt || data.reservationExpiresAt || data.dispatchExpiresAt);
    const lastTouched = readMillis(data.updatedAt || data.createdAt);
    const stale = active && (
      (Boolean(expiry) && expiry <= now.getTime()) ||
      (Boolean(lastTouched) && now.getTime() - lastTouched >= expirationMs)
    );
    if (active && !stale) summary.active += 1;
    if (stale) {
      summary.stale += 1;
      summary.refs.push(doc.ref);
    }
  });
  return summary;
}

async function pipelineHealthReport(db, {now = new Date(), expirationMs = 24 * 60 * 60 * 1000, limit = 500} = {}) {
  const deliverySnapshot = await db.collection("deliveryRequests").limit(limit).get();
  let activeDeliveries = 0;
  let searchingDeliveries = 0;
  const staleDeliveryRefs = [];
  deliverySnapshot.docs.forEach((doc) => {
    const delivery = doc.data() || {};
    const statuses = [
      delivery.status,
      delivery.deliveryStatus,
      delivery.flowStatus,
      delivery.matchingStatus,
      delivery.dispatchStatus,
    ].map(normalize);
    const protectedLive = statuses.some((status) => protectedStatuses.has(status));
    if (protectedLive || hasAssignedRider(delivery)) activeDeliveries += 1;
    if (statuses.some((status) => founderPurgeOpenStatuses.has(status))) {
      searchingDeliveries += 1;
      if (canFounderPurgeDelivery(delivery, now, expirationMs)) {
        staleDeliveryRefs.push(doc.ref);
      }
    }
  });

  const transient = {};
  for (const collection of transientDeliveryCollections) {
    transient[collection] = await scanTransientHealth(db, collection, now, expirationMs, limit);
  }
  const activeRiderOffers = [...offerCollections].reduce((sum, key) => sum + (transient[key] ? transient[key].active : 0), 0);
  const expiredRiderOffers = [...offerCollections].reduce((sum, key) => sum + (transient[key] ? transient[key].stale : 0), 0);
  const activeReservations = [...reservationCollections].reduce((sum, key) => sum + (transient[key] ? transient[key].active : 0), 0);
  const staleReservations = [...reservationCollections].reduce((sum, key) => sum + (transient[key] ? transient[key].stale : 0), 0);
  const activeQueueEntries = [...queueCollections].reduce((sum, key) => sum + (transient[key] ? transient[key].active : 0), 0);
  const staleQueueEntries = [...queueCollections].reduce((sum, key) => sum + (transient[key] ? transient[key].stale : 0), 0);
  const temporaryIrisSessions = [...irisTemporaryCollections].reduce((sum, key) => sum + (transient[key] ? transient[key].active : 0), 0);
  const orphanedIrisSessions = [...irisTemporaryCollections].reduce((sum, key) => sum + (transient[key] ? transient[key].stale : 0), 0);

  const report = {
    activeDeliveries,
    searchingDeliveries,
    staleSearchingDeliveries: staleDeliveryRefs.length,
    activeRiderOffers,
    expiredRiderOffers,
    activeReservations,
    staleReservations,
    activeQueueEntries,
    staleQueueEntries,
    temporaryIrisSessions,
    orphanedIrisSessions,
    dispatchHealthScore: 100,
  };
  report.dispatchHealthScore = pipelineHealthScore(report);
  return {
    report,
    staleDeliveryRefs,
    staleTransientRefs: Object.fromEntries(Object.entries(transient).map(([key, value]) => [key, value.refs])),
  };
}

function founderPurgePatch({founderUid, reason, now = FieldValue.serverTimestamp()}) {
  return {
    status: "expired",
    deliveryStatus: "expired",
    flowStatus: "expired",
    matchingStatus: "expired",
    dispatchStatus: "expired",
    broadcastBlocked: true,
    broadcastBlockReason: "founder_test_pipeline_purge",
    active: false,
    expired: true,
    staleArchived: true,
    staleState: "expired",
    removedFromActiveQueues: true,
    founderPipelinePurged: true,
    founderPipelinePurgeReason: reason,
    founderPipelinePurgedAt: now,
    founderPipelinePurgedBy: founderUid,
    updatedAt: now,
    offerExpiresAt: now,
    dispatchExpiresAt: now,
    matchingExpiresAt: now,
  };
}

async function matchingDocs(db, collection, deliveryId, requestId) {
  const byPath = new Map();
  const direct = await db.collection(collection).doc(deliveryId).get();
  if (direct.exists) byPath.set(direct.ref.path, direct.ref);
  const fields = [
    ["deliveryId", deliveryId],
    ["requestId", requestId],
    ["bookingId", requestId],
  ].filter(([, value]) => nonEmpty(value));
  const snapshots = await Promise.all(fields.map(([field, value]) =>
    db.collection(collection).where(field, "==", value).limit(50).get().catch(() => null)));
  snapshots.filter(Boolean).forEach((snapshot) => {
    snapshot.docs.forEach((doc) => byPath.set(doc.ref.path, doc.ref));
  });
  return [...byPath.values()];
}

function clearTransientPatch({deliveryId, founderUid, reason}) {
  return {
    deliveryId,
    status: "cleared",
    active: false,
    removedFromActiveQueues: true,
    clearedBy: founderUid,
    clearReason: reason,
    clearedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
}

function pipelineResetPatch({deliveryId, adminUid, reason}) {
  return {
    ...clearTransientPatch({deliveryId, founderUid: adminUid, reason}),
    pipelineHealthReset: true,
    pipelineHealthResetBy: adminUid,
    pipelineHealthResetReason: reason,
  };
}

function archiveExpiredPatch(delivery, now = FieldValue.serverTimestamp()) {
  const missing = missingCanonicalFields(delivery);
  return {
    status: "archived_expired",
    deliveryStatus: "archived_expired",
    flowStatus: "archived_expired",
    matchingStatus: "blocked",
    dispatchStatus: "blocked",
    broadcastBlocked: true,
    broadcastBlockReason: "archived_expired",
    active: false,
    archived: true,
    staleArchived: true,
    staleState: "archived_expired",
    staleReasons: missing,
    removedFromActiveQueues: true,
    systemArchived: true,
    staleCleanupReason: "Automatic cleanup archived stale or incomplete booking older than 24 hours.",
    archivedAt: now,
    archivedByAdminId: "system",
    archivedByAdminEmail: "system@circum",
    updatedAt: now,
  };
}

const archiveExpiredDeliveries = functions.pubsub
    .schedule("every 24 hours")
    .timeZone("Europe/London")
    .onRun(async () => {
      const db = getFirestore();
      const now = new Date();
      const snapshot = await db.collection("deliveryRequests").limit(500).get();
      const batch = db.batch();
      const affected = [];
      snapshot.docs.forEach((doc) => {
        const delivery = doc.data();
        if (!canAutoArchiveExpired(delivery, now)) return;
        affected.push(doc.id);
        const patch = archiveExpiredPatch(delivery);
        batch.set(doc.ref, patch, {merge: true});
        batch.set(db.collection("adminAuditLogs").doc(), {
          action: "delivery_auto_archived_expired",
          actionType: "delivery_auto_archived_expired",
          recordType: "deliveryRequests",
          recordId: doc.id,
          previousStatus: delivery.status || "",
          newStatus: "archived_expired",
          reason: patch.staleCleanupReason,
          staleReasons: patch.staleReasons,
          createdAt: FieldValue.serverTimestamp(),
          adminUserId: "system",
          adminEmail: "system@circum",
        });
      });
      if (affected.length > 0) {
        const logRef = db.collection("deliveryCleanupRuns").doc();
        batch.set(logRef, {
          type: "archive_expired_deliveries",
          count: affected.length,
          deliveryIds: affected,
          createdAt: FieldValue.serverTimestamp(),
        });
        await batch.commit();
      }
      console.log("archiveExpiredDeliveries", {count: affected.length, affected});
      return {count: affected.length, affected};
    });

function purgeFounderTestPipeline() {
  return functions.runWith({enforceAppCheck: true}).https.onCall(async (data, context) => {
    const founder = assertFounder(context);
    const db = getFirestore();
    const reason = `${data && data.reason || ""}`.trim().slice(0, 1000);
    if (reason.length < 12) {
      throw new functions.https.HttpsError("invalid-argument", "A detailed purge reason is required.");
    }
    const limit = Math.min(Math.max(Number(data && data.limit) || 200, 1), 500);
    const expirationHours = Math.min(Math.max(Number(data && data.expirationHours) || 24, 1), 168);
    const expirationMs = expirationHours * 60 * 60 * 1000;
    const now = new Date();
    const snapshot = await db.collection("deliveryRequests").limit(limit).get();
    const eligible = snapshot.docs.filter((doc) =>
      canFounderPurgeDelivery(doc.data(), now, expirationMs));

    const result = {
      deliveriesExpired: [],
      reservationsReleased: 0,
      offersRemoved: 0,
      queueEntriesCleared: 0,
      errors: [],
    };
    const batch = db.batch();
    for (const doc of eligible) {
      const delivery = doc.data() || {};
      const requestId = `${delivery.requestId || delivery.bookingId || doc.id}`.trim();
      result.deliveriesExpired.push(doc.id);
      batch.set(doc.ref, founderPurgePatch({
        founderUid: founder.uid,
        reason,
      }), {merge: true});
      batch.set(db.collection("adminAuditLogs").doc(), {
        action: "founder_test_pipeline_purged",
        actionType: "founder_test_pipeline_purged",
        recordType: "deliveryRequests",
        recordId: doc.id,
        previousStatus: delivery.status || "",
        newStatus: "expired",
        reason,
        founderUid: founder.uid,
        founderEmail: founder.email,
        createdAt: FieldValue.serverTimestamp(),
      });
      batch.set(db.collection("founderAuthorityAudit").doc(), {
        founderUid: founder.uid,
        founderEmail: founder.email,
        targetUid: delivery.senderId || delivery.userId || null,
        action: "purge_founder_test_pipeline",
        recordType: "deliveryRequests",
        recordId: doc.id,
        previousValues: {
          status: delivery.status || null,
          dispatchStatus: delivery.dispatchStatus || null,
          matchingStatus: delivery.matchingStatus || null,
          riderId: delivery.riderId || delivery.assignedRiderId || null,
        },
        newValues: {
          status: "expired",
          dispatchStatus: "expired",
          matchingStatus: "expired",
        },
        reason,
        createdAt: FieldValue.serverTimestamp(),
        immutable: true,
      });

      for (const collection of transientDeliveryCollections) {
        try {
          const refs = await matchingDocs(db, collection, doc.id, requestId);
          refs.forEach((ref) => {
            batch.set(ref, clearTransientPatch({
              deliveryId: doc.id,
              founderUid: founder.uid,
              reason,
            }), {merge: true});
          });
          if (collection.includes("Offer") || collection.includes("offer")) {
            result.offersRemoved += refs.length;
          } else if (collection.includes("Reservation") || collection.includes("reservation")) {
            result.reservationsReleased += refs.length;
          } else {
            result.queueEntriesCleared += refs.length;
          }
        } catch (error) {
          result.errors.push({deliveryId: doc.id, collection, message: error.message});
        }
      }
    }
    if (result.deliveriesExpired.length > 0 || result.errors.length > 0) {
      batch.set(db.collection("deliveryCleanupRuns").doc(), {
        type: "purge_founder_test_pipeline",
        founderUid: founder.uid,
        count: result.deliveriesExpired.length,
        deliveryIds: result.deliveriesExpired,
        reservationsReleased: result.reservationsReleased,
        offersRemoved: result.offersRemoved,
        queueEntriesCleared: result.queueEntriesCleared,
        errors: result.errors,
        reason,
        createdAt: FieldValue.serverTimestamp(),
      });
      await batch.commit();
    }
    return {ok: result.errors.length === 0, ...result};
  });
}

function pipelineHealthReset() {
  return functions.runWith({enforceAppCheck: true}).https.onCall(async (data, context) => {
    const adminUid = requireAdmin(context, "Operations Admin access is required.");
    const db = getFirestore();
    const reason = `${data && data.reason || ""}`.trim().slice(0, 1000);
    if (reason.length < 12) {
      throw new functions.https.HttpsError("invalid-argument", "A detailed reset reason is required.");
    }
    const limit = Math.min(Math.max(Number(data && data.limit) || 300, 1), 500);
    const expirationHours = Math.min(Math.max(Number(data && data.expirationHours) || 24, 1), 168);
    const expirationMs = expirationHours * 60 * 60 * 1000;
    const now = new Date();
    const before = await pipelineHealthReport(db, {now, expirationMs, limit});
    const batch = db.batch();
    const maxCleanupWrites = 430;
    let cleanupWrites = 0;
    const summary = {
      deliveriesExpired: 0,
      offersRemoved: 0,
      reservationsReleased: 0,
      queueEntriesCleared: 0,
      irisSessionsCleaned: 0,
      temporaryCachesCleared: 0,
      errors: [],
    };

    for (const ref of before.staleDeliveryRefs) {
      if (cleanupWrites >= maxCleanupWrites) {
        summary.errors.push({
          path: ref.path,
          code: "cleanup_write_limit_deferred",
        });
        continue;
      }
      const doc = await ref.get();
      const delivery = doc.data() || {};
      if (!canFounderPurgeDelivery(delivery, now, expirationMs)) continue;
      summary.deliveriesExpired += 1;
      cleanupWrites += 1;
      batch.set(ref, founderPurgePatch({founderUid: adminUid, reason}), {merge: true});
    }

    Object.entries(before.staleTransientRefs).forEach(([collection, refs]) => {
      refs.forEach((ref) => {
        if (cleanupWrites >= maxCleanupWrites) {
          summary.errors.push({
            collection,
            path: ref.path,
            code: "cleanup_write_limit_deferred",
          });
          return;
        }
        cleanupWrites += 1;
        batch.set(ref, pipelineResetPatch({
          deliveryId: ref.id,
          adminUid,
          reason,
        }), {merge: true});
      });
      if (offerCollections.has(collection)) summary.offersRemoved += refs.length;
      else if (reservationCollections.has(collection)) summary.reservationsReleased += refs.length;
      else if (queueCollections.has(collection)) summary.queueEntriesCleared += refs.length;
      else if (irisTemporaryCollections.has(collection)) summary.irisSessionsCleaned += refs.length;
      else summary.temporaryCachesCleared += refs.length;
    });

    const audit = {
      action: "pipeline_health_reset",
      actionType: "pipeline_health_reset",
      recordType: "dispatchPipeline",
      recordId: `pipeline-health-reset-${Date.now()}`,
      adminUserId: adminUid,
      adminEmail: context.auth.token.email || "",
      reason,
      before: before.report,
      summary,
      createdAt: FieldValue.serverTimestamp(),
      immutable: true,
    };
    const auditRef = db.collection("adminAuditLogs").doc();
    const runRef = db.collection("deliveryCleanupRuns").doc();
    batch.set(auditRef, audit);
    batch.set(runRef, {
      type: "pipeline_health_reset",
      adminUserId: adminUid,
      reason,
      before: before.report,
      summary,
      auditId: auditRef.id,
      createdAt: FieldValue.serverTimestamp(),
    });
    await batch.commit();

    const after = await pipelineHealthReport(db, {now: new Date(), expirationMs, limit});
    await runRef.set({after: after.report, completedAt: FieldValue.serverTimestamp()}, {merge: true});
    return {
      ok: summary.errors.length === 0,
      auditId: auditRef.id,
      before: before.report,
      after: after.report,
      ...summary,
    };
  });
}

module.exports = {
  archiveExpiredDeliveries,
  archiveExpiredPatch,
  canAutoArchiveExpired,
  canFounderPurgeDelivery,
  founderPurgePatch,
  isArchiveRecord,
  missingCanonicalFields,
  pipelineHealthReport,
  pipelineHealthReset,
  pipelineHealthScore,
  purgeFounderTestPipeline,
};
