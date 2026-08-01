const assert = require("node:assert/strict");
const test = require("node:test");

const {buildRiderVehicleSnapshot} = require("./rider-vehicle-snapshot");

test("buildRiderVehicleSnapshot uses the active backend vehicle", () => {
  const snapshot = buildRiderVehicleSnapshot({
    vehicleType: "Bike",
    vehicleRegistration: "OLD-123",
    vehicle: {
      type: "Motorbike",
      manufacturer: "Honda",
      model: "PCX",
      colour: "Blue",
      registration: "AB12 CDE",
      capacity: "Medium",
      insurance: "Submitted",
      mot: "Not required",
      verificationStatus: "verified",
    },
  });

  assert.deepEqual(snapshot, {
    type: "Motorbike",
    manufacturer: "Honda",
    model: "PCX",
    colour: "Blue",
    registration: "AB12 CDE",
    capacity: "Medium",
    insurance: "Submitted",
    mot: "Not required",
    verificationStatus: "verified",
  });
});

test("buildRiderVehicleSnapshot falls back to legacy fields", () => {
  const snapshot = buildRiderVehicleSnapshot({
    vehicleType: "Bike",
    vehicleRegistration: "ZX99 YYY",
  });

  assert.deepEqual(snapshot, {
    type: "Motorbike",
    registration: "ZX99 YYY",
  });
});

test("buildRiderVehicleSnapshot returns an immutable copy", () => {
  const rider = {
    vehicle: {
      type: "Car",
      manufacturer: "Toyota",
      model: "Yaris",
      colour: "Black",
      registration: "YY24 CAR",
    },
  };
  const snapshot = buildRiderVehicleSnapshot(rider);
  rider.vehicle.model = "Changed";

  assert.equal(snapshot.model, "Yaris");
});
