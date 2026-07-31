const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

test("accepted delivery writes every rider assignment alias used by Rider surfaces", () => {
  const source = fs.readFileSync(
      path.join(__dirname, "accept-ride-requests.js"),
      "utf8",
  );

  assert.match(source, /status: "accepted",\s+deliveryStatus: "accepted",\s+deliveryStage: "accepted"/s);
  assert.match(source, /riderId,\s+driverId: riderId,\s+assignedRider: riderId,\s+assignedDriverId: riderId,\s+assignedRiderId: riderId/s);
});

test("accept rejects stale, assigned, unpaid, or terminal offers with diagnostics", () => {
  const source = fs.readFileSync(
      path.join(__dirname, "accept-ride-requests.js"),
      "utf8",
  );

  assert.match(source, /const terminalStatuses = new Set/);
  assert.match(source, /const offerExclusionReason = \(delivery = \{\}, riderId = "", now = Date\.now\(\)\) =>/);
  assert.match(source, /already_assigned/);
  assert.match(source, /expired_offer/);
  assert.match(source, /payment_not_confirmed/);
  assert.match(source, /rider_offer_accept_attempt/);
  assert.match(source, /rider_offer_accept_rejected/);
  assert.match(source, /rider_offer_accept_success/);
});
