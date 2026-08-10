/* eslint-disable require-jsdoc */
const DISCREPANCY_REASONS = Object.freeze([
  "weight_exceeded",
  "dimensions_exceeded",
  "additional_undeclared_items",
  "item_differs_from_booking",
]);

const OFF_PLATFORM_PATTERNS = Object.freeze([
  /\bcash\b/i,
  /\bbank\s*transfer\b/i,
  /\bdirect\s*payment\b/i,
  /\bpay\s+me\b/i,
  /\btransfer\s+me\b/i,
]);

function money(value) {
  return Math.round((Number(value) || 0) * 100) / 100;
}

function isMaterialDiscrepancy({
  reason,
  originalWeightKg,
  observedWeightKg,
  vehicleSuitabilityChanged = false,
}) {
  if (!DISCREPANCY_REASONS.includes(reason)) return false;
  if (reason === "additional_undeclared_items" || vehicleSuitabilityChanged) {
    return true;
  }
  const original = Number(originalWeightKg) || 0;
  const observed = Number(observedWeightKg) || 0;
  return original > 0 && observed >= original * 1.2;
}

function additionalAmount(originalQuote, revisedQuote) {
  return money(Math.max(0, money(revisedQuote) - money(originalQuote)));
}

function containsOffPlatformPaymentLanguage(message) {
  return OFF_PLATFORM_PATTERNS.some(
      (pattern) => pattern.test(`${message || ""}`),
  );
}

function buildAdjustment(input) {
  const now = input.timestamp || Date.now();
  return {
    adjustmentType: "delivery_load_discrepancy",
    bookingId: input.bookingId,
    bookingRequestId: input.bookingRequestId,
    senderId: input.senderId,
    riderId: input.riderId,
    originalQuote: money(input.originalQuote),
    revisedQuote: money(input.revisedQuote),
    additionalAmount: additionalAmount(input.originalQuote, input.revisedQuote),
    riderReason: input.riderReason,
    riderNotes: input.riderNotes || "",
    evidencePhotos: input.evidencePhotos || [],
    observations: input.observations || {},
    senderDecision: "pending",
    status: "awaiting_admin_review",
    irisCalculationMetadata: input.irisCalculationMetadata || {},
    originalQuoteSnapshot: input.originalQuoteSnapshot || {},
    revisedQuoteSnapshot: input.revisedQuoteSnapshot || {},
    fraudFlag: false,
    fraudStatus: "not_flagged",
    createdAt: now,
    updatedAt: now,
  };
}

module.exports = {
  DISCREPANCY_REASONS,
  additionalAmount,
  buildAdjustment,
  containsOffPlatformPaymentLanguage,
  isMaterialDiscrepancy,
};
