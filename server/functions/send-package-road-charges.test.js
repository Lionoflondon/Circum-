"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {rankDispatchCandidates} = require("./send-package");

const nearChargeable = {
  id: "near-car",
  distanceFromPickup: 1,
  incrementalRoadChargePence: 900,
};
const fartherExempt = {
  id: "farther-motorbike",
  distanceFromPickup: 2,
  incrementalRoadChargePence: 0,
};

test("Standard dispatch may prefer lower lawful incremental road cost", () => {
  assert.deepEqual(
      rankDispatchCandidates([nearChargeable, fartherExempt], {selectedSpeed: "Standard"})
          .map((rider) => rider.id),
      ["farther-motorbike", "near-car"],
  );
});

test("Express urgency remains ahead of road-cost optimisation", () => {
  assert.deepEqual(
      rankDispatchCandidates([fartherExempt, nearChargeable], {selectedSpeed: "Express"})
          .map((rider) => rider.id),
      ["near-car", "farther-motorbike"],
  );
});
