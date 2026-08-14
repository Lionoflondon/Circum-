/* eslint-disable require-jsdoc, max-len */
const LEGEND_LIMIT = 1500;

const normalize = (value) => `${value || ""}`.trim().toLowerCase();

function isEligibleLegendDelivery(delivery) {
  const status = normalize(delivery.status || delivery.deliveryStatus);
  const payment = normalize(delivery.paymentStatus || delivery.stripePaymentStatus || delivery.payment && delivery.payment.status);
  const refund = normalize(delivery.refundStatus);
  const cancelled = delivery.cancelled === true || status.includes("cancel");
  const refunded = delivery.refunded === true || ["refunded", "partially_refunded"].includes(refund) || status === "refunded";
  return ["delivered", "completed"].includes(status) &&
    ["paid", "succeeded", "success"].includes(payment) && !cancelled && !refunded;
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

module.exports = {LEGEND_LIMIT, isEligibleLegendDelivery, nextLegendNumber, legendAwardDecision};
