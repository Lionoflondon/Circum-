/* eslint-disable max-len */
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

test("accepted delivery persists the authoritative assigned vehicle snapshot", () => {
  const source = fs.readFileSync(
      path.join(__dirname, "accept-ride-requests.js"),
      "utf8",
  );

  assert.match(source, /buildRiderVehicleSnapshot\(rider\)/);
  assert.match(source, /assignedVehicleId/);
  assert.match(source, /assignedVehicleClass/);
  assert.match(source, /assignedVehicleSnapshot/);
});

test("customer Rider projection is bounded, truthful, and strips private vehicle data", () => {
  const {customerSafeRiderProjection, customerSafeVehicle} =
    require("./accept-ride-requests")._private;
  const vehicle = customerSafeVehicle({
    type: "Car",
    manufacturer: "Volvo",
    model: "EX30",
    colour: "Blue",
    registration: "AB12 CDE",
    verificationStatus: "verified",
    insurance: "private-policy",
    mot: "private-mot",
    capacity: "private-capacity",
  });
  const projection = customerSafeRiderProjection("rider-1", {
    fullName: "Ayo Rider",
    username: "@ayo",
    profilePhotoUrl: "https://images.example/rider.jpg",
    riderRank: "veteran",
    rankOverride: true,
    verificationStatus: "verified",
    completedDeliveries: 42,
    averageRating: 4.8,
    phoneNumber: "+447000000000",
    email: "private@example.com",
    earnings: 900,
  }, {requiresVanguard: true}, vehicle);

  assert.equal(projection.username, "ayo");
  assert.equal(projection.rank, "veteran");
  assert.equal(projection.rankAssigned, true);
  assert.equal(projection.verified, true);
  assert.equal(projection.rating, 4.8);
  assert.deepEqual(projection.qualifications, ["Vanguard"]);
  assert.equal("insurance" in projection.vehicle, false);
  assert.equal("mot" in projection.vehicle, false);
  assert.equal("capacity" in projection.vehicle, false);
  assert.equal("phoneNumber" in projection, false);
  assert.equal("email" in projection, false);
  assert.equal("earnings" in projection, false);
});

test("acceptance overwrites all reassignment-sensitive Rider identity fields", () => {
  const source = fs.readFileSync(path.join(__dirname, "accept-ride-requests.js"), "utf8");
  for (const field of [
    "assignedRiderProfile", "riderPhotoUrl", "riderPhotoVersion",
    "riderUsername", "riderRank", "riderRankAssigned", "riderVerified",
    "riderCompletedDeliveries", "riderRating", "riderQualifications",
    "assignedVehicleSnapshot",
  ]) {
    assert.match(source, new RegExp(`${field}: customer`));
  }
});

test("profile changes refresh only the Rider's current canonical assignment", () => {
  const source = fs.readFileSync(path.join(__dirname, "platform-notifications.js"), "utf8");
  const start = source.indexOf("exports.onRiderProfileUpdated");
  const end = source.indexOf("exports.onPayoutUpdated", start);
  const handler = source.slice(start, end);
  assert.match(handler, /riderPresence/);
  assert.match(handler, /activeDeliveryId/);
  assert.match(handler, /assignedRiderId\(delivery\.data\(\)\) !== riderId/);
  assert.match(handler, /customerSafeRiderProjection/);
  assert.match(handler, /assignedRiderProfile: projection/);
  assert.doesNotMatch(handler, /where\("assignedRiderId"/);
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

test("accepted rider payload never exposes personal phone numbers to sender surfaces", () => {
  const source = fs.readFileSync(
      path.join(__dirname, "accept-ride-requests.js"),
      "utf8",
  );
  const payloadStart = source.indexOf("const riderPayload =");
  const payloadEnd = source.indexOf("const findDeliveryRequest", payloadStart);
  const payloadSource = source.slice(payloadStart, payloadEnd);

  assert.match(payloadSource, /phoneNumber: "",/);
  assert.match(payloadSource, /contactMethod: "circum_relay"/);
  assert.match(payloadSource, /maskedCommunicationOnly: true/);
  assert.doesNotMatch(payloadSource, /cleanText\(rider\.phone/);
  assert.doesNotMatch(payloadSource, /rider\.phoneNumber/);
  assert.doesNotMatch(payloadSource, /rider\.mobile/);
  assert.doesNotMatch(payloadSource, /fcmToken/);
  assert.doesNotMatch(payloadSource, /code:/);
});

test("acceptance uses the shared eligibility predicate and atomically reserves Rider presence", () => {
  const source = fs.readFileSync(path.join(__dirname, "accept-ride-requests.js"), "utf8");
  assert.match(source, /dispatchEligibilityDecision\(\{/);
  assert.match(source, /transaction\.get\(presenceRef\)/);
  assert.match(source, /availabilityStatus: "busy"/);
  assert.match(source, /activeDeliveryId: found\.id/);
  assert.doesNotMatch(source, /adminVehicleOverride/);
});

test("acceptance notification derives the Sender identity and never reads a token from delivery", () => {
  const source = fs.readFileSync(path.join(__dirname, "accept-ride-requests.js"), "utf8");
  assert.match(source, /communicationEngine\.emitNotification/);
  assert.match(source, /recipientId: senderId/);
  assert.doesNotMatch(source, /deliveryRequest\.fcmToken/);
  assert.doesNotMatch(source, /deliveryRequest\.pushToken/);
});
