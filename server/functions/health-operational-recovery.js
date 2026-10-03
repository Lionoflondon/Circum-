/* eslint-disable max-len, require-jsdoc */
"use strict";
const {FieldValue} = require("firebase-admin/firestore");
const {createHash} = require("node:crypto");
const {buildCustodyEvent, buildHealthPlusPlanFields} = require("./health-plus-core");
const templates = require("./transactional-email-templates");
function monthKey(value) {
  const date = value?.toDate ? value.toDate() : new Date(value);
  if (!Number.isFinite(date.getTime())) return null;
  return new Intl.DateTimeFormat("en-GB", {timeZone: "Europe/London", year: "numeric", month: "2-digit"}).format(date);
}

async function projectOperational({db, event}) {
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(event.deliveryId || "") || !event.eventId || event.eventId.length > 128) throw Object.assign(new Error("invalid_health_operational_event"), {statusCode: 400});
  const receipt = db.collection("eventHandlerClaims").doc("health_operational_" + createHash("sha256").update(event.eventId).digest("hex"));
  const source = db.collection("prescriptionPickups").doc(event.deliveryId);
  return db.runTransaction(async (tx) => {
    const [claim, snap] = await Promise.all([tx.get(receipt), tx.get(source)]);
    if (claim.exists) return {outcome: "DUPLICATE", changed: 0};
    if (!snap.exists) {
      tx.create(receipt, {handler: "health_operational", reason: "source_deleted", createdAt: FieldValue.serverTimestamp()});
      return {outcome: "IGNORED", changed: 0};
    }
    const pickup = {...snap.data(), id: event.deliveryId};
    const status = pickup.status || "scheduled";
    // Historical transport payloads do not rewind custody or emit old updates.
    if (!event.after || (event.after.status || "scheduled") !== status || (event.after.assignedDriverId || null) !== (pickup.assignedDriverId || null)) {
      tx.create(receipt, {handler: "health_operational", reason: "stale_event", createdAt: FieldValue.serverTimestamp()});
      return {outcome: "IGNORED", changed: 0};
    }
    const descriptor = require("./health-plus-operations")._private.STATUS_EVENTS[status];
    if (event.before && (event.before.status || "scheduled") === status && (event.before.assignedDriverId || null) === (pickup.assignedDriverId || null)) {
      tx.create(receipt, {handler: "health_operational", reason: "unchanged_operational_state", createdAt: FieldValue.serverTimestamp()});
      return {outcome: "IGNORED", changed: 0};
    }
    if (!descriptor) {
      tx.create(receipt, {handler: "health_operational", reason: "unsupported_status", createdAt: FieldValue.serverTimestamp()});
      return {outcome: "IGNORED", changed: 0};
    }
    const custodyRef = db.collection("healthPlusCustodyArchive").doc(`${pickup.id}_${descriptor[0]}_${status}`);
    const notificationId = `health_${pickup.id}_${descriptor[0]}`;
    const noticeRef = db.collection("healthPlusNotifications").doc(notificationId);
    const emailRef = db.collection("emailQueue").doc(notificationId);
    const usageRef = db.collection("healthPlusUsageEvents").doc(`operational_delivery_${pickup.id}`);
    const scheduleRef = status === "delivered" && pickup.scheduleId ? db.collection("recurringPickupSchedules").doc(pickup.scheduleId) : null;
    const reviewRef = db.collection("healthPlusOperationalErrors").doc(`delivery_usage_${pickup.id}`);
    const [custody, notice, email, usage, schedule, review] = await Promise.all([tx.get(custodyRef), tx.get(noticeRef), tx.get(emailRef), tx.get(usageRef), scheduleRef ? tx.get(scheduleRef) : null, tx.get(reviewRef)]);
    let changed = 0; let needsReview = false;
    if (!custody.exists) {
      tx.create(custodyRef, {
        pickupId: pickup.id, profileId: pickup.profileId || null, scheduleId: pickup.scheduleId || null, userId: pickup.userId || pickup.senderId || null,
        ...buildCustodyEvent({eventType: descriptor[0], actorType: pickup.lastAdminId ? "admin" : pickup.assignedDriverId ? "rider" : "system", actorId: pickup.lastAdminId || pickup.assignedDriverId || null, actorName: pickup.assignedDriverName || null, publicMessage: descriptor[1], internalNote: pickup.adminNote || null, statusAfterEvent: descriptor[2]}), createdAt: FieldValue.serverTimestamp(),
      }); changed++;
    }
    if (["assigned", "collected", "out_for_delivery", "delivered", "rescheduled", "escalated"].includes(status)) {
      if (!notice.exists) {
        tx.create(noticeRef, {id: notificationId, userId: pickup.userId || pickup.senderId || null, senderId: pickup.senderId || pickup.userId || null, profileId: pickup.profileId || null, pickupId: pickup.id, type: descriptor[0], title: "Health+ update", body: descriptor[1], source: "health_plus", read: false, createdAt: FieldValue.serverTimestamp()}); changed++;
      }
      if (pickup.email && !email.exists) {
        const template = templates.healthUpdate({type: status === "rescheduled" ? "scheduled" : status});
        tx.create(emailRef, {notificationId, to: pickup.email, subject: template.subject, text: template.text, html: template.html, preheader: template.preheader, heading: template.heading, ctaLabel: template.ctaLabel, ctaUrl: template.ctaUrl, templateId: template.templateId, providerTags: template.providerTags, status: "queued", eventType: `health_plus_${descriptor[0]}`, source: "health_plus", senderCategory: "health", sourceCollection: "prescriptionPickups", sourceDocumentId: pickup.id, relatedEntityId: pickup.id, sourceRequiredStatus: status, maxAttempts: 5, createdAt: FieldValue.serverTimestamp(), sourceRecipientField: "email", updatedAt: FieldValue.serverTimestamp()}); changed++;
      }
    }
    if (schedule?.exists && !usage.exists) {
      const plan = schedule.data();
      const deliveryMonth = monthKey(pickup.deliveredAt || pickup.completedAt || event.time || snap.updateTime);
      if (custody.exists || deliveryMonth !== monthKey(new Date())) {
        // The old non-atomic handler may already have counted this pickup.
        // Never infer an additional entitlement debit from missing new receipts.
        needsReview = true;
        if (!review.exists) tx.create(reviewRef, {pickupId: pickup.id, scheduleId: pickup.scheduleId, status: "manual_review", reason: custody.exists ? "legacy_usage_commit_unknown" : "prior_cycle_delivery_event", retryable: false, createdAt: FieldValue.serverTimestamp()});
      } else {
        const previous = Number(plan.usedDeliveriesThisCycle ?? plan.usedPickupsThisCycle ?? 0);
        if (!Number.isFinite(previous) || previous < 0) throw new Error("invalid_health_usage_counter");
        const used = previous + 1;
        const fields = buildHealthPlusPlanFields(plan.planType || plan.subscriptionPlan, {...plan, usedDeliveriesThisCycle: used, usedPickupsThisCycle: used});
        tx.set(scheduleRef, {...fields, preferredRiderId: plan.preferredRiderId || pickup.assignedDriverId || null, preferredRiderName: plan.preferredRiderName || pickup.assignedDriverName || null, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
        tx.create(usageRef, {pickupId: pickup.id, scheduleId: pickup.scheduleId, type: "delivery_usage_committed", createdAt: FieldValue.serverTimestamp()}); changed++;
      }
    }
    tx.create(receipt, {handler: "health_operational", eventId: event.eventId, changed, needsReview, createdAt: FieldValue.serverTimestamp()});
    return {outcome: needsReview ? "MANUAL_REVIEW" : "APPLIED", changed, needsReview};
  });
}
module.exports = {projectOperational};
