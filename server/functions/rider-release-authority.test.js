"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const {ASSIGNMENT_FIELDS, assignedRiderId} = require("./delivery-assignment");
test("assignment normalization accepts supported aliases and rejects conflicts", () => {
  for (const field of ASSIGNMENT_FIELDS) assert.equal(assignedRiderId({[field]: "rider"}), "rider");
  assert.equal(assignedRiderId({riderId: "a", assignedRiderId: "b"}), "");
  assert.equal(assignedRiderId({}), "");
});
test("tracking cancel uses release authority", () => {
  assert.match(fs.readFileSync(`${__dirname}/delivery-tracking.js`, "utf8"), /nextStatus === "cancelled"[\s\S]*requestRiderCancellationHandler/);
});
