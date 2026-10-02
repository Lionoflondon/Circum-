/* eslint-disable max-len, require-jsdoc */
"use strict";
const {FieldValue} = require("firebase-admin/firestore");
const {normalizeDeepLink} = require("./notification-deep-links");
function notificationInput({key, recipientId = null, recipientRole, type, title, body, deliveryId, data = {}}) {
 const destination = normalizeDeepLink(null, {type, recipientRole, data: {...data, deliveryId, bookingId: deliveryId}});
 return {key, payload: {recipientId, recipientRole, type, title, body, message: body, bookingId: deliveryId, destination, deepLink: destination, data: {...data, deliveryId, bookingId: deliveryId, destination}, category: recipientRole === "rider" ? "jobs" : "system", read: false, archived: false, deliveryStatus: "persisted", deliveryState: "persisted", pushDeliveryStatus: "failed", failureReason: "retry_worker_exited_before_send", retryable: true, deliveryAttempts: 0, retryCount: 0, createdAt: FieldValue.serverTimestamp()}};
}
async function queueNotifications(tx, db, inputs) {
 const refs = inputs.map((x) => db.collection("notifications").doc(`event_${Buffer.from(x.key).toString("base64url")}`));
 const existing = await Promise.all(refs.map((r) => tx.get(r)));
 refs.forEach((ref, i) => {
if (!existing[i].exists) tx.create(ref, {...inputs[i].payload, notificationId: ref.id, correlationId: ref.id, dedupeKey: inputs[i].key});
});
 return refs.map((r) => r.id);
}

module.exports = {notificationInput, queueNotifications};
