"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {canonicalEventType, timelineEventsForChange} = require("./movement-timeline");

test("delivery writes project payment, assignment and lifecycle events", () => {
  const events = timelineEventsForChange({status: "requested", paymentStatus: "pending"}, {status: "accepted", paymentStatus: "succeeded", riderId: "rider-1"});
  const types = events.map((event) => canonicalEventType(event, {}, {status: "accepted"})).filter(Boolean);
  assert.deepEqual(types, ["PaymentConfirmed", "RiderAssigned", "RiderAccepted"]);
});

test("terminal lifecycle maps to one canonical completion event", () => {
  const events = timelineEventsForChange({status: "arrived_at_dropoff"}, {status: "completed"});
  assert.deepEqual(events.map((event) => canonicalEventType(event, {}, {status: "completed"})), ["Completed"]);
});

test("Admin operational changes project an auditable override event", () => {
  const events = timelineEventsForChange(
      {status: "accepted"},
      {status: "accepted", adminOperationStatus: "escalated", adminOperationUpdatedBy: "Operations Admin"},
  );
  assert.equal(canonicalEventType(events[0], {}, {}), "AdminOverride");
  assert.equal(events[0].actorType, "admin");
});
