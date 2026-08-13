/* eslint-disable require-jsdoc, max-len */
const LEGEND_LIMIT = 1000;

const RECOGNITION_CONFIG = Object.freeze({
  legend: {
    limit: LEGEND_LIMIT,
    recognitionKey: "legend",
    rootField: "isLegend",
    numberField: "legendNumber",
    awardedAtField: "legendAwardedAt",
    sourceField: "legendSource",
    reasonField: "legendReason",
    revokedAtField: "legendRevokedAt",
    revokedByField: "legendRevokedBy",
    revokeReasonField: "legendRevokeReason",
  },
  foundingRider: {
    limit: LEGEND_LIMIT,
    recognitionKey: "foundingRider",
    rootField: "isFoundingRider",
    numberField: "foundingRiderNumber",
    awardedAtField: "foundingRiderAwardedAt",
    sourceField: "foundingRiderSource",
    reasonField: "foundingRiderReason",
    revokedAtField: "foundingRiderRevokedAt",
    revokedByField: "foundingRiderRevokedBy",
    revokeReasonField: "foundingRiderRevokeReason",
  },
  patron: {
    limit: LEGEND_LIMIT,
    recognitionKey: "patron",
    rootField: "isPatron",
    numberField: "patronNumber",
    awardedAtField: "patronAwardedAt",
    sourceField: "patronSource",
    reasonField: "patronReason",
    revokedAtField: "patronRevokedAt",
    revokedByField: "patronRevokedBy",
    revokeReasonField: "patronRevokeReason",
  },
});

const normalize = (value) => `${value || ""}`.trim().toLowerCase();

function isEligibleLegendDelivery(delivery) {
  const status = normalize(delivery.status || delivery.deliveryStatus);
  const payment = normalize(delivery.paymentStatus || delivery.stripePaymentStatus || delivery.payment && delivery.payment.status);
  const refund = normalize(delivery.refundStatus);
  const cancelled = delivery.cancelled === true || status.includes("cancel");
  const refunded = delivery.refunded === true || ["refunded", "partially_refunded"].includes(refund) || status === "refunded";
  return status === "completed" && ["paid", "succeeded", "success"].includes(payment) && !cancelled && !refunded;
}

function nextLegendNumber(totalAwarded, limit = LEGEND_LIMIT) {
  const total = Number(totalAwarded || 0);
  const cap = Number(limit || LEGEND_LIMIT);
  return total >= cap ? null : total + 1;
}

function legendAwardDecision({delivery, user = {}, counter = {}}) {
  if (!isEligibleLegendDelivery(delivery) || user.isLegend === true) return null;
  return nextLegendNumber(counter.totalAwarded, counter.limit || LEGEND_LIMIT);
}

function recognitionConfig(type) {
  const rawType = `${type || ""}`.trim();
  const config = RECOGNITION_CONFIG[rawType] || RECOGNITION_CONFIG[normalize(rawType)];
  if (!config) throw new Error(`Unsupported recognition type: ${type}`);
  return config;
}

function recognitionAwardDecision({type, subject = {}, counter = {}}) {
  const config = recognitionConfig(type);
  const recognitions = subject.recognitions && typeof subject.recognitions === "object" ?
    subject.recognitions :
    {};
  const recognition = recognitions[config.recognitionKey] || {};
  if (subject[config.rootField] === true || recognition.awarded === true) return null;
  return nextLegendNumber(counter.totalAwarded, counter.limit || config.limit);
}

function buildRecognitionPatch({type, number, awardedBy, source, reason, timestampValue}) {
  const config = recognitionConfig(type);
  return {
    [config.rootField]: true,
    [config.numberField]: number,
    [config.awardedAtField]: timestampValue,
    [config.sourceField]: source,
    [config.reasonField]: reason || null,
    recognitions: {
      [config.recognitionKey]: {
        awarded: true,
        number,
        awardedAt: timestampValue,
        awardedBy,
        source,
        reason: reason || null,
      },
    },
  };
}

function buildRecognitionRevokePatch({type, revokedBy, reason, timestampValue}) {
  const config = recognitionConfig(type);
  return {
    [config.rootField]: false,
    [config.revokedAtField]: timestampValue,
    [config.revokedByField]: revokedBy,
    [config.revokeReasonField]: reason || null,
    recognitions: {
      [config.recognitionKey]: {
        awarded: false,
        revokedAt: timestampValue,
        revokedBy,
        reason: reason || null,
      },
    },
  };
}

module.exports = {
  RECOGNITION_CONFIG,
  LEGEND_LIMIT,
  isEligibleLegendDelivery,
  nextLegendNumber,
  legendAwardDecision,
  recognitionConfig,
  recognitionAwardDecision,
  buildRecognitionPatch,
  buildRecognitionRevokePatch,
};
