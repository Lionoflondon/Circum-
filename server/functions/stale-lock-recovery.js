/* eslint-disable max-len, require-jsdoc */
"use strict";
const {FieldValue, FieldPath} = require("firebase-admin/firestore");
const {evaluateDeliveryLock, statusOf, hasPickupEvidence} = require("./stale-delivery-core");
const text = (x) => String(x || "").trim();
async function reconcileOne({db, riderId, expectedDeliveryId, now = Date.now()}) {
  const presenceRef = db.collection("riderPresence").doc(riderId);
  return db.runTransaction(async (tx) => {
    const presenceSnap = await tx.get(presenceRef);
    if (!presenceSnap.exists) return {repaired: 0, queued: 0};
    const presence = presenceSnap.data();
    const deliveryId = text(presence.activeDeliveryId || presence.currentDeliveryId);
    if (!deliveryId || (expectedDeliveryId && deliveryId !== expectedDeliveryId)) return {repaired: 0, queued: 0};
    const deliveryRef = db.collection("deliveryRequests").doc(deliveryId);
    const [deliverySnap, trackingSnap, queueSnap] = await Promise.all([
      tx.get(deliveryRef), tx.get(deliveryRef.collection("tracking").doc("liveLocation")),
      tx.get(db.collection("staleDeliveryQueue").doc(deliveryId)),
    ]);
    const delivery = deliverySnap.exists ? {...deliverySnap.data(), _lastTrackingAt: trackingSnap.data()?.updatedAt} : null;
    const decision = evaluateDeliveryLock(delivery, {exists: deliverySnap.exists, now});
    if (!decision.repair && !decision.review) return {repaired: 0, queued: 0};
    if (decision.repair) {
      // Both aliases must still refer to this delivery. An inconsistent alias
      // can represent newer active work and must never be erased by cleanup.
      if ([presence.activeDeliveryId, presence.currentDeliveryId].some((id) => text(id) && text(id) !== deliveryId)) return {repaired: 0, queued: 0, conflicted: 1};
      tx.set(presenceRef, {activeDeliveryId: FieldValue.delete(), currentDeliveryId: FieldValue.delete(), busy: false,
        availabilityStatus: presence.isOnline === true ? "available" : "offline", updatedAt: FieldValue.serverTimestamp(), source: "staleDeliveryReconciliation"}, {merge: true});
      tx.set(db.collection("riderOperationalAudit").doc(`stale_lock_${riderId}_${deliveryId}`),
          {riderId, deliveryId, action: "stale_active_delivery_reference_repaired", reason: decision.reason, actorUid: "system", createdAt: FieldValue.serverTimestamp()}, {merge: true});
    }
    tx.set(db.collection("staleDeliveryQueue").doc(deliveryId), {deliveryId, riderId, deliveryStatus: delivery ? statusOf(delivery) : "missing",
      reason: decision.reason, paymentStatus: text(delivery?.paymentStatus), pickupOccurred: delivery ? hasPickupEvidence(delivery) : false,
      status: decision.review || decision.archive ? "needs_review" : "reference_repaired",
      firstDetectedAt: queueSnap.data()?.firstDetectedAt || FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()}, {merge: true});
    return {repaired: decision.repair ? 1 : 0, queued: decision.review || decision.archive ? 1 : 0};
  });
}
async function reconcileStaleLocks({db, limit = 20, now = Date.now()}) {
  const stateRef = db.collection("operationsState").doc("stale_lock_cursor");
  const cursor = (await stateRef.get()).data()?.cursor;
  const query = db.collection("riderPresence").orderBy(FieldPath.documentId()).limit(limit);
  let snap = await (cursor ? query.startAfter(cursor) : query).get();
  if (snap.empty && cursor) snap = await query.get();
  const result = {scanned: snap.size, repaired: 0, queued: 0, conflicted: 0};
  for (const doc of snap.docs) {
    const outcome = await reconcileOne({db, riderId: doc.id, expectedDeliveryId: text(doc.data().activeDeliveryId || doc.data().currentDeliveryId), now});
    for (const field of ["repaired", "queued", "conflicted"]) result[field] += outcome[field] || 0;
  }
  await stateRef.set({cursor: snap.size === limit ? snap.docs.at(-1).id : null}, {merge: true});
  return result;
}
module.exports = {reconcileOne, reconcileStaleLocks};
