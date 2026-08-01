/* eslint-disable max-len */
const test = require("node:test");
const assert = require("node:assert/strict");
const {
  normalizeVehicleClass,
  normalizeRiderVehicle,
  pickRequiredVehicle,
  vehicleCanHandle,
  riderVehicleMatchesRequest,
} = require("./vehicle-dispatch");

test("vehicle normalization supports legacy aliases", () => {
  assert.equal(normalizeVehicleClass("bicycle"), "motorbike");
  assert.equal(normalizeVehicleClass("motorcycle"), "motorbike");
  assert.equal(normalizeVehicleClass("estate-suv"), "car");
  assert.equal(normalizeVehicleClass("small van"), "van");
  assert.equal(normalizeVehicleClass("large van"), "van");
  assert.equal(normalizeVehicleClass("luton"), "van");
  assert.equal(normalizeRiderVehicle({vehicle: {type: "SUV"}}), "car");
});

test("vehicle compatibility matrix protects oversized jobs", () => {
  assert.equal(vehicleCanHandle("motorbike", "motorbike"), true);
  assert.equal(vehicleCanHandle("car", "motorbike"), true);
  assert.equal(vehicleCanHandle("bike", "car"), false);
  assert.equal(vehicleCanHandle("car", "van"), false);
  assert.equal(vehicleCanHandle("van", "motorbike"), true);
  assert.equal(vehicleCanHandle("van", "car"), true);
  assert.equal(vehicleCanHandle("van", "van"), true);
  assert.equal(vehicleCanHandle("luton", "motorbike"), true);
  assert.equal(vehicleCanHandle("luton", "car"), true);
  assert.equal(vehicleCanHandle("luton", "van"), true);
});

test("required vehicle is read from IRIS and request fields", () => {
  assert.equal(pickRequiredVehicle({vehicleRequirement: "Van"}), "van");
  assert.equal(pickRequiredVehicle({irisPrivate: {internal: {riderMatching: {vehicleRequired: "estate"}}}}), "car");
  assert.equal(pickRequiredVehicle({matchingRequirements: {requiredVehicle: "luton"}}), "van");
});

test("motorbike rider cannot accept van job", () => {
  assert.equal(riderVehicleMatchesRequest({vehicleType: "Bike"}, {requiredVehicle: "Van"}), false);
});

test("van rider can accept motorbike car and van jobs", () => {
  const rider = {vehicleType: "Van"};
  assert.equal(riderVehicleMatchesRequest(rider, {requiredVehicle: "Motorbike"}), true);
  assert.equal(riderVehicleMatchesRequest(rider, {requiredVehicle: "Car"}), true);
  assert.equal(riderVehicleMatchesRequest(rider, {requiredVehicle: "Van"}), true);
});

test("luton rider can accept all jobs", () => {
  const rider = {vehicleType: "Luton"};
  for (const requiredVehicle of ["motorbike", "car", "van"]) {
    assert.equal(riderVehicleMatchesRequest(rider, {requiredVehicle}), true);
  }
});

test("car rider cannot accept van job", () => {
  const rider = {vehicleType: "Car"};
  assert.equal(riderVehicleMatchesRequest(rider, {requiredVehicle: "Van"}), false);
  assert.equal(riderVehicleMatchesRequest(rider, {requiredVehicle: "Luton"}), false);
});
