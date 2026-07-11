/* eslint-disable require-jsdoc, max-len */
const RECOGNITION_CONFIG = {
  legend: {
    limit: 1000,
    numberWidth: 4,
    awardField: "legend",
    flatAwardedField: "isLegend",
    flatNumberField: "legendNumber",
    flatAwardedAtField: "legendAwardedAt",
    flatAwardedByField: "legendAwardedBy",
  },
  foundingRider: {
    limit: 1000,
    numberWidth: 4,
    awardField: "foundingRider",
    flatAwardedField: "isFoundingRider",
    flatNumberField: "foundingRiderNumber",
    flatAwardedAtField: "foundingRiderAwardedAt",
    flatAwardedByField: "foundingRiderAwardedBy",
  },
  patron: {
    limit: 100,
    numberWidth: 3,
    awardField: "patron",
    flatAwardedField: "isPatron",
    flatNumberField: "patronNumber",
    flatAwardedAtField: "patronAwardedAt",
    flatAwardedByField: "patronAwardedBy",
  },
};
const LEGEND_LIMIT = RECOGNITION_CONFIG.legend.limit;

const normalize = (value) => `${value || ""}`.trim().toLowerCase();

function isEligibleLegendDelivery(delivery) {
  const status = normalize(delivery.status || delivery.deliveryStatus);
  const payment = normalize(delivery.paymentStatus || delivery.stripePaymentStatus || delivery.payment && delivery.payment.status);
  const refund = normalize(delivery.refundStatus);
  const cancelled = delivery.cancelled === true || status.includes("cancel");
  const refunded = delivery.refunded === true || refund === "refunded" || status === "refunded";
  return status === "completed" && ["paid", "succeeded", "success"].includes(payment) && !cancelled && !refunded;
}

function nextLegendNumber(totalAwarded, limit = LEGEND_LIMIT) {
  const total = Number(totalAwarded || 0);
  const cap = Number(limit || LEGEND_LIMIT);
  return total >= cap ? null : total + 1;
}

function recognitionConfig(type) {
  const key = `${type || ""}`.trim();
  if (!Object.prototype.hasOwnProperty.call(RECOGNITION_CONFIG, key)) {
    throw new Error(`Unsupported recognition type: ${type}`);
  }
  return RECOGNITION_CONFIG[key];
}

function formatRecognitionNumber(type, number) {
  const config = recognitionConfig(type);
  const value = Number(number || 0);
  return `${value}`.padStart(config.numberWidth, "0");
}

function recognitionAwardDecision({type, subject = {}, counter = {}}) {
  const config = recognitionConfig(type);
  const nested = subject.recognitions && subject.recognitions[config.awardField];
  if (subject[config.flatAwardedField] === true || nested && nested.awarded === true) return null;
  const total = Number(counter.totalAwarded || 0);
  return total >= config.limit ? null : total + 1;
}

function buildRecognitionPatch({type, number, awardedBy, source, reason, timestampValue}) {
  const config = recognitionConfig(type);
  const awardedAt = timestampValue || null;
  const recognition = {
    awarded: true,
    number,
    numberLabel: formatRecognitionNumber(type, number),
    awardedAt,
    awardedBy: awardedBy || "system",
    source: source || "system",
    reason: reason || null,
  };
  return {
    recognitions: {[config.awardField]: recognition},
    [config.flatAwardedField]: true,
    [config.flatNumberField]: number,
    [config.flatAwardedAtField]: awardedAt,
    [config.flatAwardedByField]: awardedBy || "system",
  };
}

function buildRecognitionRevokePatch({type, revokedBy, reason, timestampValue}) {
  const config = recognitionConfig(type);
  return {
    recognitions: {
      [config.awardField]: {
        awarded: false,
        revokedAt: timestampValue || null,
        revokedBy: revokedBy || "admin",
        revokeReason: reason || null,
      },
    },
    [config.flatAwardedField]: false,
  };
}

function legendAwardDecision({delivery, user = {}, counter = {}}) {
  if (!isEligibleLegendDelivery(delivery) || user.isLegend === true) return null;
  return nextLegendNumber(counter.totalAwarded, counter.limit || LEGEND_LIMIT);
}

module.exports = {
  LEGEND_LIMIT,
  RECOGNITION_CONFIG,
  isEligibleLegendDelivery,
  nextLegendNumber,
  legendAwardDecision,
  recognitionConfig,
  formatRecognitionNumber,
  recognitionAwardDecision,
  buildRecognitionPatch,
  buildRecognitionRevokePatch,
};
