/* eslint-disable max-len, require-jsdoc */
const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");

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
  const vanguardEnabled = delivery.vanguardEnabled === true ||
    delivery.vanguardProtocolEnabled === true ||
    delivery.vanguardRequired === true;
  if (vanguardEnabled) {
    requireAny("pickup PIN", [
      delivery.pickupPin,
      delivery.collectionPin,
      delivery.vanguardProtection && delivery.vanguardProtection.collectionPin,
    ]);
    requireAny("drop-off PIN", [
      delivery.dropoffPin,
      delivery.deliveryPin,
      delivery.vanguardProtection && delivery.vanguardProtection.deliveryPin,
    ]);
  }
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

module.exports = {
  archiveExpiredDeliveries,
  archiveExpiredPatch,
  canAutoArchiveExpired,
  isArchiveRecord,
  missingCanonicalFields,
};
