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
  assert.equal(normalizeVehicleClass("bicycle"), "bike");
  assert.equal(normalizeVehicleClass("motorcycle"), "bike");
  assert.equal(normalizeVehicleClass("estate-suv"), "estate_suv");
  assert.equal(normalizeVehicleClass("small van"), "van");
  assert.equal(normalizeVehicleClass("large van"), "luton_van");
  assert.equal(normalizeVehicleClass("luton"), "luton_van");
  assert.equal(normalizeRiderVehicle({vehicle: {type: "SUV"}}), "estate_suv");
});

test("vehicle compatibility matrix protects oversized jobs", () => {
  assert.equal(vehicleCanHandle("bike", "bike"), true);
  assert.equal(vehicleCanHandle("car", "bike"), true);
  assert.equal(vehicleCanHandle("bike", "car"), false);
  assert.equal(vehicleCanHandle("car", "van"), false);
  assert.equal(vehicleCanHandle("van", "bike"), true);
  assert.equal(vehicleCanHandle("van", "car"), true);
  assert.equal(vehicleCanHandle("van", "van"), true);
  assert.equal(vehicleCanHandle("luton", "bike"), true);
  assert.equal(vehicleCanHandle("luton", "car"), true);
  assert.equal(vehicleCanHandle("luton", "estate_suv"), true);
  assert.equal(vehicleCanHandle("luton", "van"), true);
  assert.equal(vehicleCanHandle("luton", "luton_van"), true);
});

test("required vehicle is read from IRIS and request fields", () => {
  assert.equal(pickRequiredVehicle({vehicleRequirement: "Van"}), "van");
  assert.equal(pickRequiredVehicle({irisPrivate: {internal: {riderMatching: {vehicleRequired: "estate"}}}}), "estate_suv");
  assert.equal(pickRequiredVehicle({matchingRequirements: {requiredVehicle: "luton"}}), "luton_van");
});

test("bike rider cannot accept van job", () => {
  assert.equal(riderVehicleMatchesRequest({vehicleType: "Bike"}, {requiredVehicle: "Van"}), false);
});

test("van rider can accept bike car and van jobs", () => {
  const rider = {vehicleType: "Van"};
  assert.equal(riderVehicleMatchesRequest(rider, {requiredVehicle: "Bike"}), true);
  assert.equal(riderVehicleMatchesRequest(rider, {requiredVehicle: "Car"}), true);
  assert.equal(riderVehicleMatchesRequest(rider, {requiredVehicle: "Van"}), true);
});

test("luton rider can accept all jobs", () => {
  const rider = {vehicleType: "Luton"};
  for (const requiredVehicle of ["bike", "car", "estate_suv", "van", "luton_van"]) {
    assert.equal(riderVehicleMatchesRequest(rider, {requiredVehicle}), true);
  }
});

test("car rider cannot accept van or luton job", () => {
  const rider = {vehicleType: "Car"};
  assert.equal(riderVehicleMatchesRequest(rider, {requiredVehicle: "Van"}), false);
  assert.equal(riderVehicleMatchesRequest(rider, {requiredVehicle: "Luton"}), false);
});
