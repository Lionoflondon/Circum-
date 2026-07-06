/* eslint-disable max-len */
"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  VANGUARD_STATUSES,
  canCompleteDropoff,
  canCompletePickup,
  initialProtocolFields,
  irisRequiresVanguard,
  protocolEnabled,
} = require("./vanguard-protocol-core");
const {deliveryProtocolState} = require("./iris-core");

test("toggle enables Vanguard as delivery protocol state", () => {
  const fields = initialProtocolFields({
    itemName: "Small envelope",
    selected: true,
  });

  assert.equal(fields.vanguardProtocolEnabled, true);
  assert.equal(fields.vanguardStatus, VANGUARD_STATUSES.pickupVerificationPending);
  assert.equal(fields.vanguardProtocol.enabled, true);
  assert.equal(fields.vanguardProtocol.required, false);
  assert.deepEqual(fields.vanguardVerificationState, {
    pickup: "pending",
    custody: "pending",
    handover: "pending",
  });
});

test("IRIS can require Vanguard for protected deliveries", () => {
  assert.equal(irisRequiresVanguard({description: "passport"}), true);
  assert.equal(irisRequiresVanguard({description: "controlled medicines"}), true);
  assert.equal(irisRequiresVanguard({description: "confidential legal documents"}), true);

  const fields = initialProtocolFields({
    itemName: "Passport",
    irisRequired: true,
    irisRequiredReason: "IRIS policy requires Vanguard for passports.",
  });

  assert.equal(fields.vanguardProtocolEnabled, true);
  assert.equal(fields.vanguardProtocol.required, true);
  assert.equal(fields.vanguardRequiredReason, "IRIS policy requires Vanguard for passports.");
});

test("rider pickup and dropoff remain blocked until protocol completion", () => {
  assert.equal(canCompletePickup({
    vanguardProtocolEnabled: true,
    vanguardStatus: VANGUARD_STATUSES.pickupVerificationPending,
  }), false);
  assert.equal(canCompletePickup({
    vanguardProtocolEnabled: true,
    vanguardStatus: VANGUARD_STATUSES.secureCustody,
  }), true);
  assert.equal(canCompleteDropoff({
    vanguardProtocolEnabled: true,
    vanguardStatus: VANGUARD_STATUSES.handoverPending,
  }), false);
  assert.equal(canCompleteDropoff({
    vanguardProtocolEnabled: true,
    vanguardStatus: VANGUARD_STATUSES.handoverVerified,
  }), true);
});

test("dispatch and admin data can read protocol fields from delivery", () => {
  const delivery = {
    vanguardProtocolEnabled: true,
    vanguardStatus: VANGUARD_STATUSES.secureCustody,
    vanguardRequiredReason: "IRIS policy requires Vanguard for passports.",
  };

  assert.equal(protocolEnabled(delivery), true);
  assert.deepEqual(deliveryProtocolState(delivery), {
    vanguardProtocolEnabled: true,
    vanguardStatus: VANGUARD_STATUSES.secureCustody,
    vanguardRequiredReason: "IRIS policy requires Vanguard for passports.",
  });
});
