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
  return {
    senderId: text(delivery.senderId || delivery.userId || delivery.customerId || delivery.shipperId),
    riderId: text(delivery.riderId || delivery.driverId || delivery.assignedRiderId || delivery.assignedDriverId || delivery.assignedRider),
  };
}

function assertCompletedDelivery(delivery, senderId, now = Date.now()) {
  if (!delivery) throw new Error("delivery-not-found");
  if (!COMPLETED_STATUSES.has(normalized(delivery.deliveryState || delivery.status))) {
    throw new Error("delivery-not-completed");
  }
  const parties = deliveryParties(delivery);
  if (!parties.senderId || parties.senderId !== senderId) throw new Error("delivery-not-owned");
  if (!parties.riderId) throw new Error("delivery-rider-missing");
  const completedAt = timestampMillis(delivery.completedAt || delivery.deliveredAt || delivery.updatedAt);
  if (!completedAt || now - completedAt > RATING_WINDOW_MS) throw new Error("rating-window-closed");
  return {...parties, completedAt};
}

function normalizeRatingInput(input = {}) {
  const stars = Number(input.stars || input.starRating);
  if (!Number.isInteger(stars) || stars < 1 || stars > 5) throw new Error("invalid-rating");
  const feedback = text(input.feedback || input.feedbackText);
  if (feedback.length > MAX_FEEDBACK_LENGTH) throw new Error("feedback-too-long");
  const tags = Array.isArray(input.feedbackTags) ? input.feedbackTags.map(text) : [];
  if (tags.length > FEEDBACK_TAGS.size || tags.some((tag) => !FEEDBACK_TAGS.has(tag))) {
    throw new Error("invalid-feedback-tag");
  }
  return {stars, feedback, feedbackTags: [...new Set(tags)]};
}

function normalizeTipInput(input = {}) {
  const amountPence = Number(input.amountPence);
  if (!Number.isInteger(amountPence) || amountPence < 100 || amountPence > MAX_TIP_PENCE) {
    throw new Error("invalid-tip-amount");
  }
  const paymentMethod = normalized(input.paymentMethod);
  if (!PAYMENT_METHODS.has(paymentMethod)) throw new Error("invalid-payment-method");
  return {amountPence, amount: amountPence / 100, paymentMethod};
}

function nextRatingStats(current = {}, stars) {
  const totalRatings = Number(current.totalRatings || 0);
  const previousAverage = Number(current.averageRating || current.rating || 0);
  const nextTotal = totalRatings + 1;
  const averageRating = Math.round((((previousAverage * totalRatings) + stars) / nextTotal) * 100) / 100;
  const names = [null, "oneStarCount", "twoStarCount", "threeStarCount", "fourStarCount", "fiveStarCount"];
  return {
    averageRating,
    rating: averageRating,
    totalRatings: nextTotal,
    [names[stars]]: Number(current[names[stars]] || 0) + 1,
  };
}

function nextTipStats(current = {}, amount) {
  const previousTotal = Number(current.tipTotal || current.tipsTotal || 0);
  const previousCount = Number(current.tipCount || 0);
  const tipTotal = Math.round((previousTotal + amount) * 100) / 100;
  const tipCount = previousCount + 1;
  return {
    tipTotal,
    tipsTotal: tipTotal,
    tipCount,
    averageTip: Math.round((tipTotal / tipCount) * 100) / 100,
  };
}

module.exports = {
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
