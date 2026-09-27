"use strict";

const crypto = require("node:crypto");
const {FieldValue} = require("firebase-admin/firestore");

function text(value, max = 500) {
  return `${value || ""}`.trim().slice(0, max);
}

function reviewId({eventId, artifactType, objectId = ""}) {
  return `stripe_${crypto.createHash("sha256")
      .update([eventId, artifactType, objectId].join(":"))
      .digest("hex")
      .slice(0, 40)}`;
}

async function recordPaymentArtifactReview({db, event, artifactType, reason, objectId = "", details = {}}) {
  const eventId = text(event && event.id) || "missing_event_id";
  const ref = db.collection("paymentArtifactReconciliations").doc(reviewId({eventId, artifactType, objectId}));
  await ref.set({
    service: "stripe_webhook",
    artifactType,
    stripeEventId: eventId,
    stripeEventType: text(event && event.type),
    stripeObjectId: text(objectId),
    status: "action_required",
    reviewRequired: true,
    reason: text(reason, 160),
    details,
    updatedAt: FieldValue.serverTimestamp(),
    createdAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  return {reviewRequired: true, status: "action_required", artifactReviewId: ref.id, reason};
}

module.exports = {recordPaymentArtifactReview, reviewId};
