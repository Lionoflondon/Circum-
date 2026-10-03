/* eslint-disable max-len, require-jsdoc */
"use strict";
const {FieldValue} = require("firebase-admin/firestore");
const {canAutoArchiveExpired, archiveExpiredPatch} = require("./delivery-cleanup");
function eligible(delivery, now) {
 const state = String(delivery.status || delivery.deliveryStatus || "").toLowerCase();
 if (!["requested", "pending", "finding_rider", "recoverable_incomplete"].includes(state)) return false;
 // Cleanup has no authority over custody, reservations or provider-backed money.
 if (["riderId", "assignedRiderId", "driverId", "assignedDriverId", "paymentIntentId", "stripePaymentIntentId", "stripeCheckoutSessionId", "checkoutSessionId", "paymentSessionId", "rothReservationId", "reservationId", "settlementId"].some((key) => delivery[key])) return false;
 if (["paid", "succeeded", "success", "processing", "authorized", "refunded", "partially_refunded"].includes(String(delivery.paymentStatus || "").toLowerCase())) return false;
 return canAutoArchiveExpired(delivery, new Date(now));
}
async function archiveExpired({db, now, limit, worker}) {
 const {page} = require("./legacy-scheduled-recovery");
 const p = await page({db, collection: "deliveryRequests", worker, limit}); let archived = 0;
 for (const doc of p.snapshot.docs) {
  archived += await db.runTransaction(async (tx) => {
   const current = await tx.get(doc.ref); const delivery = current.data() || {};
   if (!current.exists || !eligible(delivery, now)) return 0;
   const audit = db.collection("adminAuditLogs").doc(`delivery_auto_archived_expired_${doc.id}`);
   const existing = await tx.get(audit);
   if (existing.exists) return 0;
   const patch = archiveExpiredPatch(delivery);
   tx.set(doc.ref, patch, {merge: true});
   tx.create(audit, {action: "delivery_auto_archived_expired", recordType: "deliveryRequests", recordId: doc.id, previousStatus: delivery.status || "", newStatus: "archived_expired", reason: patch.staleCleanupReason, staleReasons: patch.staleReasons, createdAt: FieldValue.serverTimestamp(), adminUserId: "system", adminEmail: "system@circum"});
   return 1;
  });
 }
 await p.save(); return {scanned: p.snapshot.size, archived};
}
module.exports = {eligible, archiveExpired};
