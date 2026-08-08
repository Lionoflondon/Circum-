"use strict";

const TERMINAL_DELIVERY_STATUSES = new Set([
  "delivered", "completed", "cancelled", "canceled", "failed",
  "expired", "blocked", "refunded", "archived",
]);

function normalizeStatus(value) {
  return `${value || ""}`.trim().toLowerCase().replace(/[-\s]+/g, "_");
}

function isTerminalDeliveryStatus(value) {
  return TERMINAL_DELIVERY_STATUSES.has(normalizeStatus(value));
}

module.exports = {TERMINAL_DELIVERY_STATUSES, isTerminalDeliveryStatus, normalizeStatus};
