"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const scheduled = require("./scheduled-delivery-core");

const future = "2099-08-14T12:00:00.000Z";
const past = "2020-08-14T12:00:00.000Z";

test("Gift always binds to the unified scheduled engine without implied assignment", () => {
  const gift = {
    productType: "gift",
    readyForDispatch: true,
  };
  assert.equal(scheduled.fulfilmentStrategy(gift), scheduled.STRATEGIES.SCHEDULED_DELIVERY);
  assert.equal(scheduled.assignedRiderId(gift), "");
  assert.equal(scheduled.activationState(gift), "ready_dispatch");
  assert.equal(scheduled.isOpenDispatchOffer(gift), true);
});

test("future Gift waits then becomes a competitive offer at activation", () => {
  const gift = {productType: "gift", readyForDispatch: true, scheduledAt: future};
  assert.equal(scheduled.activationState(gift), "scheduled");
  assert.equal(scheduled.isOpenDispatchOffer(gift), false);
  assert.equal(scheduled.activationState({...gift, scheduledAt: past}), "ready_dispatch");
  assert.equal(scheduled.isOpenDispatchOffer({...gift, scheduledAt: past}), true);
  assert.deepEqual(scheduled.activationPlan(gift), {
    activate: false,
    mode: null,
    riderBusy: false,
    status: "",
  });
  assert.deepEqual(scheduled.activationPlan({...gift, scheduledAt: past}), {
    activate: true,
    mode: "open_dispatch",
    riderBusy: false,
    status: "requested",
  });
});

test("Gift scheduling does not imply Rider pre-assignment", () => {
  const gift = {productType: "gift", scheduledAt: future};
  assert.equal(scheduled.assignedRiderId(gift), "");
  assert.equal(scheduled.scheduledJobProjection("gift_1", gift).assignedRiderId, "");
});

test("an explicit Admin-reserved Gift stays isolated to its Rider", () => {
  const gift = {
    productType: "gift",
    scheduledAt: future,
    assignedRiderId: "rider-1",
    riderReservationMode: "admin_reserved",
  };
  const projection = scheduled.scheduledJobProjection("gift_1", gift);
  assert.equal(projection.assignedRiderId, "rider-1");
  assert.equal(projection.domainBadge, "Gift");
  assert.equal(scheduled.canStartScheduledDelivery(gift, "rider-1"), false);
  assert.equal(scheduled.canStartScheduledDelivery({...gift, scheduledAt: past}, "rider-1"), true);
  assert.equal(scheduled.canStartScheduledDelivery({...gift, scheduledAt: past}, "rider-2"), false);
  assert.equal(scheduled.activationPlan({...gift, scheduledAt: past}).riderBusy, true);
});

test("Health+ remains competitive by default", () => {
  const health = {
    productType: "health_plus",
    readyForCollection: true,
    scheduledPickupDate: future,
  };
  assert.equal(scheduled.fulfilmentStrategy(health), scheduled.STRATEGIES.OPEN_DISPATCH);
  assert.equal(scheduled.isOpenDispatchOffer(health), true);
});

test("Health+ enters the same scheduled engine only with explicit timing intent", () => {
  const health = {
    productType: "health_plus",
    useScheduledDeliveryEngine: true,
    scheduledAt: future,
  };
  assert.equal(scheduled.fulfilmentStrategy(health), scheduled.STRATEGIES.SCHEDULED_DELIVERY);
  assert.equal(scheduled.activationState(health), "scheduled");
  assert.equal(scheduled.isOpenDispatchOffer(health), false);
  assert.equal(scheduled.activationState({...health, scheduledAt: past}), "ready_dispatch");
});

test("Standard supports immediate and scheduled routing through one policy", () => {
  assert.equal(
      scheduled.fulfilmentStrategy({productType: "standard", deliveryTime: {type: "now"}}),
      scheduled.STRATEGIES.OPEN_DISPATCH,
  );
  assert.equal(
      scheduled.fulfilmentStrategy({productType: "standard", deliveryTime: {type: "scheduled", scheduledJourneyAt: future}}),
      scheduled.STRATEGIES.SCHEDULED_DELIVERY,
  );
});

test("scheduled TP policy is domain-correct", () => {
  assert.equal(scheduled.trustPointsForScheduledDelivery({productType: "standard"}), 5);
  assert.equal(scheduled.trustPointsForScheduledDelivery({productType: "gift"}), 5);
  assert.equal(scheduled.trustPointsForScheduledDelivery({productType: "health_plus"}), 6);
});

test("terminal scheduled records never reactivate", () => {
  for (const status of ["delivered", "completed", "cancelled", "failed"]) {
    const delivery = {productType: "gift", status, scheduledAt: past};
    assert.equal(scheduled.activationState(delivery), "terminal");
    assert.equal(scheduled.isOpenDispatchOffer(delivery), false);
  }
});

test("scheduled projection contains the Rider operational contract", () => {
  const projection = scheduled.scheduledJobProjection("delivery-1", {
    productType: "health_plus",
    useScheduledDeliveryEngine: true,
    assignedRiderId: "rider-1",
    scheduledAt: future,
    scheduledWindow: "12:00-13:00",
    pickupAddress: "Pharmacy",
    dropoffAddress: "Patient",
    riderPayout: 14.5,
    packageDescription: "Sealed collection",
    status: "scheduled",
  });
  assert.deepEqual(
      Object.keys(projection).sort(),
      [
        "activationState", "assignedRiderId", "deliveryId", "domainBadge",
        "earnings", "fulfilmentStrategy", "instructions", "pickupAddress",
        "productType", "requestId", "scheduledAt", "scheduledWindow",
        "serviceType", "status", "dropoffAddress",
      ].sort(),
  );
  assert.equal(projection.domainBadge, "Health+");
  assert.equal(projection.earnings, 14.5);
});
