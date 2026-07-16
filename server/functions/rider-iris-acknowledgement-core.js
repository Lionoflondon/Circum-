/* eslint-disable max-len, require-jsdoc */

const PICKUP_CONFIRMATION_STAGES = new Set([
  "arrived_at_pickup",
  "pickup_verification",
  "parcel_verification_required",
  "pickup_verified",
  "parcel_verified",
]);

function text(value) {
  return `${value || ""}`.trim();
}

function lifecycleStage(delivery) {
  return text(delivery.deliveryStage || delivery.deliveryStatus || delivery.status)
      .toLowerCase();
}

function canConfirmAtPickup(delivery) {
  const stage = lifecycleStage(delivery);
  if (PICKUP_CONFIRMATION_STAGES.has(stage)) return true;
  if (stage !== "waiting") return false;
  const waiting = delivery.waiting && typeof delivery.waiting === "object" ? delivery.waiting : {};
  return text(waiting.phase || "pickup").toLowerCase() !== "dropoff";
}

function irisAssessment(delivery) {
  if (delivery.irisRecommendation && typeof delivery.irisRecommendation === "object") {
    return delivery.irisRecommendation;
  }
  if (delivery.iris && typeof delivery.iris === "object") return delivery.iris;
  return null;
}

function irisVersion(delivery, assessment) {
  return text(
      delivery.irisAssessmentVersion ||
      delivery.irisVersion ||
      (assessment && (assessment.version || assessment.modelVersion)),
  ) || null;
}

function itemSnapshotReference(delivery) {
  return text(
      delivery.itemSnapshotReference ||
      delivery.parcelSnapshotReference ||
      delivery.parcelPhotoUrl ||
      delivery.itemPhotoUrl,
  ) || null;
}

function buildAcknowledgement({deliveryId, riderId, delivery}) {
  const assessment = irisAssessment(delivery);
  const version = irisVersion(delivery, assessment);
  const snapshotReference = itemSnapshotReference(delivery);
  return {
    deliveryId,
    riderId,
    status: "confirmed",
    acknowledgementStatus: "confirmed",
    ...(assessment ? {irisAssessment: assessment} : {}),
    ...(version ? {irisVersion: version} : {}),
    ...(snapshotReference ? {itemSnapshotReference: snapshotReference} : {}),
    source: "rider_pickup_iris_confirmation",
  };
}

module.exports = {
  buildAcknowledgement,
  canConfirmAtPickup,
  lifecycleStage,
};
