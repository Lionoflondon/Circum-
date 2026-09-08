"use strict";

const ASSIGNMENT_FIELDS = Object.freeze([
  "riderId", "driverId", "assignedRider", "assignedRiderId", "assignedDriverId", "courierId",
]);

// Conflicting identities are never resolved by choosing whichever alias is first.
function assignedRiderId(delivery = {}) {
  const ids = [...new Set(ASSIGNMENT_FIELDS.map((key) => `${delivery[key] || ""}`.trim()).filter(Boolean))];
  return ids.length === 1 ? ids[0] : "";
}

module.exports = {ASSIGNMENT_FIELDS, assignedRiderId};
