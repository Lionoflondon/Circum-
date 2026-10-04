/* eslint-disable max-len, require-jsdoc */
"use strict";
const {FieldValue} = require("firebase-admin/firestore");
const {healthMovement} = require("./movement-ledger");
const {riderId, terminal, active} = require("./delivery-write-recovery");
const {createHash} = require("node:crypto");
const normalized = (v) => String(v || "").toLowerCase().replace(/[\s-]+/g, "_");
function claimRef(db, kind, event) {
 if (!/^[A-Za-z0-9_-]{1,128}$/.test(event.deliveryId || "") || !event.eventId || event.eventId.length > 128) throw Object.assign(new Error("invalid_delivery_event"), {statusCode: 400});
 return db.collection("eventHandlerClaims").doc("special_movement_" + createHash("sha256").update(`${kind}:${event.eventId}`).digest("hex"));
}
async function projectHealth({db, event}) {
 const claim = claimRef(db, "health", event); const pickup = db.collection("prescriptionPickups").doc(event.deliveryId); const delivery = db.collection("deliveryRequests").doc(`health_${event.deliveryId}`);
 return db.runTransaction(async (tx) => {
  const [receipt, source, target, payment] = await Promise.all([tx.get(claim), tx.get(pickup), tx.get(delivery), tx.get(db.collection("healthPlusPayments").doc(event.deliveryId))]);
  if (receipt.exists) return {outcome: "DUPLICATE", changed: 0};
  const current = source.data() || {}; const previous = target.data() || {}; const money = payment.data() || {};
  let changed = 0; let reason = "source_deleted";
  if (source.exists && current.deliveryId && current.deliveryId !== delivery.id) reason = "source_identity_conflict";
  else if (source.exists) {
   // A projection never owns an accepted assignment or a terminal delivery.
   // Source/payment reads participate in the same transaction as the target.
   const custody = target.exists && (active(previous) || terminal(previous) || riderId(previous));
   if (custody) {
    reason = "canonical_delivery_preserved";
    if (previous.sourceModule === "health_plus" && previous.healthPlusPickupId === event.deliveryId && !previous.healthOrderId) {
     tx.set(delivery, {healthOrderId: event.deliveryId}, {merge: true}); changed = 1;
    }
   } else if (target.exists && (previous.sourceModule !== "health_plus" || previous.healthPlusPickupId !== event.deliveryId)) reason = "target_identity_conflict";
   else {
    const movement = Object.fromEntries(Object.entries(healthMovement(event.deliveryId, current, money)).filter(([, v]) => v !== undefined));
    const paid = normalized(money.paymentStatus || money.status || current.paymentStatus) === "paid" && !["refunded", "partially_refunded", "cancelled", "canceled", "failed"].includes(normalized(money.refundStatus || current.refundStatus));
    if (!paid && !terminal(current)) Object.assign(movement, {status: "scheduled", matchingStatus: "held", dispatchStatus: "held", healthDispatchReady: false, readyForCollection: false});
    tx.set(delivery, {...movement, healthMovementSourceVersion: source.updateTime}, {merge: true}); changed = 1; reason = paid ? "projected" : "unpaid_held";
   }
   if (current.deliveryId !== delivery.id || current.serviceType !== "HEALTH_PLUS" || current.sourceModule !== "health_plus") tx.set(pickup, {deliveryId: delivery.id, serviceType: "HEALTH_PLUS", sourceModule: "health_plus", movementLinkedAt: FieldValue.serverTimestamp()}, {merge: true});
  }
  tx.create(claim, {handler: "health_movement", eventId: event.eventId, changed, reason, createdAt: FieldValue.serverTimestamp()}); return {outcome: "APPLIED", changed, reason};
 });
}
async function projectTerminal({db, event}) {
 const claim = claimRef(db, "terminal", event); const delivery = db.collection("deliveryRequests").doc(event.deliveryId);
 return db.runTransaction(async (tx) => {
  const [receipt, source] = await Promise.all([tx.get(claim), tx.get(delivery)]);
  if (receipt.exists) return {outcome: "DUPLICATE", changed: 0};
  const current = source.data() || {}; const state = normalized(current.status || current.deliveryStatus);
  const collection = current.sourceModule === "gifts" ? "giftRequests" : current.sourceModule === "health_plus" ? "prescriptionPickups" : null;
  const id = current.sourceModule === "gifts" ? current.giftRequestId : current.healthPlusPickupId;
  const linked = collection && /^[A-Za-z0-9_-]{1,128}$/.test(id || "") ? db.collection(collection).doc(id) : null;
  const target = linked ? await tx.get(linked) : null; const before = target?.data() || {};
  let changed = 0; let reason = "not_terminal_or_linked";
  if (source.exists && ["delivered", "cancelled"].includes(state) && target?.exists) {
   const targetState = normalized(before.status || before.deliveryStatus);
   if ((before.deliveryId && before.deliveryId !== event.deliveryId) || (riderId(before) && riderId(current) && riderId(before) !== riderId(current))) reason = "newer_assignment_preserved";
   else if (terminal(before) && targetState !== state && !(state === "delivered" && ["completed", "complete"].includes(targetState))) reason = "terminal_conflict_preserved";
   else if (targetState === state || (state === "delivered" && ["completed", "complete"].includes(targetState))) reason = "already_terminal";
   else {
    const patch = {status: state, deliveryStatus: state, assignedRiderId: riderId(current) || null, updatedAt: FieldValue.serverTimestamp()};
    if (state === "delivered") Object.assign(patch, {deliveredAt: current.deliveredAt || current.completedAt || FieldValue.serverTimestamp(), completedAt: current.completedAt || current.deliveredAt || FieldValue.serverTimestamp()});
    else patch.cancelledAt = current.cancelledAt || FieldValue.serverTimestamp();
    if (collection === "prescriptionPickups") patch.assignedDriverId = patch.assignedRiderId;
    tx.set(linked, patch, {merge: true}); changed = 1; reason = "projected";
   }
  }
  tx.create(claim, {handler: "terminal_movement", eventId: event.eventId, changed, reason, createdAt: FieldValue.serverTimestamp()}); return {outcome: "APPLIED", changed, reason};
 });
}
module.exports = {projectHealth, projectTerminal};
