"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const timeline = require("./movement-timeline");

test("canonical active movement states map to Sender-facing events", () => {
  const expected = {
    accepted: "Accepted",
    navigating_to_pickup: "Rider En Route to Pickup",
    arrived_at_pickup: "Rider Arrived at Pickup",
    collected: "Collected",
    navigating_to_dropoff: "In Transit",
    arrived_at_dropoff: "Rider Arrived at Drop-off",
    delivered: "Delivered",
  };

  for (const [status, event] of Object.entries(expected)) {
    assert.equal(timeline.eventName("STANDARD", status), event);
  }
});

test("ordinary lifecycle produces the complete ordered movement timeline", () => {
  const lifecycle = [
    "accepted",
    "navigating_to_pickup",
    "arrived_at_pickup",
    "collected",
    "navigating_to_dropoff",
    "arrived_at_dropoff",
    "delivered",
  ];
  const events = [];
  let before = {status: "requested"};

  for (const status of lifecycle) {
    const after = {status, serviceType: "STANDARD"};
    events.push(...timeline.timelineEventsForChange(before, after));
    before = after;
  }

  assert.deepEqual(events.map((event) => event.event), [
    "Accepted",
    "Rider En Route to Pickup",
    "Rider Arrived at Pickup",
    "Collected",
    "In Transit",
    "Rider Arrived at Drop-off",
    "Delivered",
  ]);
  assert.equal(events[4].status, "navigating_to_dropoff");
});

test("legacy aliases remain compatible without duplicate events", () => {
  const events = timeline.timelineEventsForChange(
      {status: "collected", sourceStatus: "picked_up"},
      {status: "navigating_to_dropoff", sourceStatus: "in_transit"},
  );

  assert.deepEqual(events.map((event) => event.event), ["In Transit"]);
  assert.equal(timeline.eventName("STANDARD", "en-route-to-pickup"),
      "Rider En Route to Pickup");
  assert.equal(timeline.eventName("STANDARD", "out_for_delivery"),
      "In Transit");
});

test("terminal and unknown statuses are handled safely", () => {
  for (const status of ["delivered", "completed", "cancelled", "failed"]) {
    assert.equal(timeline.terminalStatus(status), true);
  }
  assert.equal(timeline.terminalStatus("arrived_at_dropoff"), false);
  assert.equal(timeline.eventName("STANDARD", "unknown_future_status"), null);
  assert.deepEqual(
      timeline.timelineEventsForChange(
          {status: "accepted"},
          {status: "unknown_future_status"},
      ),
      [],
  );
});
