/* eslint-disable max-len, require-jsdoc */
"use strict";

const COMPLETED_STATUSES = new Set(["completed", "complete", "delivered"]);
const PAYMENT_METHODS = new Set(["roth", "saved_card", "card", "apple_pay", "google_pay"]);
const FEEDBACK_TAGS = new Set([
  "Friendly",
  "Professional",
  "Fast",
  "Excellent Communication",
  "Careful Handling",
  "Late",
  "Hard to find",
  "Damaged item",
  "Safety concern",
  "On time",
  "Good communication",
  "Poor communication",
]);
const RATING_WINDOW_MS = 30 * 24 * 60 * 60 * 1000;
const MAX_FEEDBACK_LENGTH = 500;
const MAX_TIP_PENCE = 10000;

const text = (value) => `${value || ""}`.trim();
const normalized = (value) => text(value).toLowerCase().replace(/[\s-]+/g, "_");

function timestampMillis(value) {
  if (value && typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  const parsed = Date.parse(`${value || ""}`);
  return Number.isFinite(parsed) ? parsed : 0;
}

function deliveryParties(delivery = {}) {
  const riders = [delivery.riderId, delivery.driverId, delivery.assignedRiderId, delivery.assignedDriverId, delivery.assignedRider].map(text).filter(Boolean);
  if (new Set(riders).size > 1) throw new Error("delivery-rider-mismatch");
  return {
    senderId: text(delivery.senderId || delivery.userId || delivery.customerId || delivery.shipperId),
    riderId: text(delivery.riderId || delivery.driverId || delivery.assignedRiderId || delivery.assignedDriverId || delivery.assignedRider),
  };
}

function assertCompletedDelivery(delivery, senderId, now = Date.now()) {
  if (!delivery) throw new Error("delivery-not-found");
  if ([delivery.deliveryState, delivery.status, delivery.deliveryStatus].some((status) => ["cancelled", "canceled", "failed", "rejected", "refunded", "voided"].includes(normalized(status))) ||
      !COMPLETED_STATUSES.has(normalized(delivery.deliveryState || delivery.status))) {
    throw new Error("delivery-not-completed");
  }
  const parties = deliveryParties(delivery);
  if (!parties.senderId || parties.senderId !== senderId) throw new Error("delivery-not-owned");
  if (!parties.riderId) throw new Error("delivery-rider-missing");
  const completedAt = timestampMillis(delivery.completedAt || delivery.deliveredAt);
  if (!completedAt || completedAt > now || now - completedAt > RATING_WINDOW_MS) throw new Error("rating-window-closed");
  return {...parties, completedAt};
}

function normalizeRatingInput(input = {}) {
  const stars = input.stars === undefined ? input.starRating : input.stars;
  if (!Number.isInteger(stars) || stars < 1 || stars > 5) throw new Error("invalid-rating");
  if ([input.feedback, input.feedbackText].some((value) => value !== undefined && typeof value !== "string")) throw new Error("invalid-feedback");
  if (input.feedbackTags !== undefined && !Array.isArray(input.feedbackTags)) throw new Error("invalid-feedback-tag");
  const feedback = text(input.feedback || input.feedbackText);
  if (feedback.length > MAX_FEEDBACK_LENGTH) throw new Error("feedback-too-long");
  const aliases = {on_time: "On time", friendly: "Friendly", careful_handling: "Careful Handling", good_communication: "Good communication", late: "Late", poor_communication: "Poor communication", damaged_item: "Damaged item", safety_concern: "Safety concern"};
  const tags = Array.isArray(input.feedbackTags) ? input.feedbackTags.map((tag) => aliases[text(tag)] || text(tag)) : [];
  if (tags.length > FEEDBACK_TAGS.size || tags.some((tag) => !FEEDBACK_TAGS.has(tag))) {
    throw new Error("invalid-feedback-tag");
  }
  return {stars, feedback, feedbackTags: [...new Set(tags)]};
}

function normalizeTipInput(input = {}) {
  const amountPence = input.amountPence;
  if (input.currency !== undefined && input.currency !== "GBP" && input.currency !== "gbp") throw new Error("invalid-tip-currency");
  if (!Number.isInteger(amountPence) || amountPence < 100 || amountPence > MAX_TIP_PENCE) {
    throw new Error("invalid-tip-amount");
  }
  const paymentMethod = normalized(input.paymentMethod);
  if (!PAYMENT_METHODS.has(paymentMethod)) throw new Error("invalid-payment-method");
  return {amountPence, amount: amountPence / 100, paymentMethod};
}

function nextRatingStats(current = {}, stars) {
  const totalRatings = Number(current.totalRatings || 0);
  if (!Number.isSafeInteger(totalRatings) || totalRatings < 0) throw new Error("rating-reconciliation-required");
  const names = [null, "oneStarCount", "twoStarCount", "threeStarCount", "fourStarCount", "fiveStarCount"];
  const histogramCount = names.slice(1).reduce((sum, name) => sum + Number(current[name] || 0), 0);
  let previousSum = current.ratingSum;
  if (!Number.isSafeInteger(previousSum)) {
    if (histogramCount === totalRatings) previousSum = names.slice(1).reduce((sum, name, index) => sum + Number(current[name] || 0) * (index + 1), 0);
    else if (totalRatings < 100) previousSum = Math.round(Number(current.averageRating || current.rating || 0) * totalRatings);
    else throw new Error("rating-reconciliation-required");
  }
  if (previousSum < totalRatings || previousSum > totalRatings * 5) throw new Error("rating-reconciliation-required");
  const ratingSum = previousSum + stars;
  const nextTotal = totalRatings + 1;
  const averageRating = Math.round((ratingSum / nextTotal) * 100) / 100;
  return {ratingSum, averageRating, rating: averageRating, totalRatings: nextTotal, [names[stars]]: Number(current[names[stars]] || 0) + 1};
}

function nextTipStats(current = {}, amount) {
  const previousTotal = Number(current.tipTotal || current.tipsTotal || 0);
  const previousCount = Number(current.tipCount || 0);
  const totalPence = Math.round(previousTotal * 100) + Math.round(amount * 100);
  const tipTotal = totalPence / 100;
  const tipCount = previousCount + 1;
  return {
    tipTotal,
    tipsTotal: tipTotal,
    tipCount,
    averageTip: Math.round((tipTotal / tipCount) * 100) / 100,
  };
}

function publicRatingFeedback(value) {
  return text(value).replace(/\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/gi, "[email removed]")
      .replace(/(?<!\w)(?:\+?\d[\d\s().-]{7,}\d)(?!\w)/g, "[phone number removed]");
}

function ratingCategories(delivery = {}) {
  const quote = delivery.pricingBreakdown || {};
  const values = [delivery.serviceType, delivery.selectedServiceType, delivery.sourceModule, delivery.deliveryType, quote.serviceType, quote.sourceModule].map(normalized);
  const result = [];
  if (values.some((v) => ["health+", "health_plus", "healthplus"].includes(v))) result.push("Health+");
  if (values.some((v) => ["gift", "gifts"].includes(v))) result.push("Gift");
  if (delivery.businessMode === true || delivery.businessId || delivery.businessAccountId || values.includes("business")) result.push("Business");
  if (delivery.isScheduled === true || delivery.scheduledAt || normalized(delivery.deliveryTime && delivery.deliveryTime.type) === "scheduled" || values.includes("scheduled")) result.push("Scheduled");
  if (delivery.vanguard === true || delivery.vanguardProtocolEnabled === true || (delivery.dispatchProtocol && delivery.dispatchProtocol.vanguard === true) || values.includes("vanguard")) result.push("Vanguard");
  if (delivery.isHeavy === true || values.includes("heavy")) result.push("Heavy");
  return result.length ? result : ["Standard"];
}

module.exports = {
  publicRatingFeedback,
  ratingCategories,
  COMPLETED_STATUSES,
  FEEDBACK_TAGS,
  MAX_FEEDBACK_LENGTH,
  MAX_TIP_PENCE,
  PAYMENT_METHODS,
  RATING_WINDOW_MS,
  assertCompletedDelivery,
  deliveryParties,
  nextRatingStats,
  nextTipStats,
  normalizeRatingInput,
  normalizeTipInput,
};
