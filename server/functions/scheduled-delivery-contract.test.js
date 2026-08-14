"use strict";

const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const assert = require("node:assert/strict");

const functionsDir = __dirname;
const root = path.join(functionsDir, "../..");
const source = fs.readFileSync(path.join(functionsDir, "scheduled-delivery.js"), "utf8");
const index = fs.readFileSync(path.join(functionsDir, "index.js"), "utf8");
const dispatch = fs.readFileSync(path.join(functionsDir, "send-package.js"), "utf8");
const offers = fs.readFileSync(path.join(functionsDir, "get-avaliable-requests.js"), "utf8");
const acceptance = fs.readFileSync(path.join(functionsDir, "accept-ride-requests.js"), "utf8");
const tracking = fs.readFileSync(path.join(functionsDir, "sender-tracking-state-core.js"), "utf8");
const rules = fs.readFileSync(path.join(root, "firestore.rules"), "utf8");
const rider = fs.readFileSync(path.join(root, "lib/website/shared/circum_website_app.dart"), "utf8");

test("scheduled engine exports its activation and Rider projection authorities", () => {
  assert.match(index, /exports\.getRiderScheduledJobs = scheduledDelivery\.getRiderScheduledJobs/);
  assert.match(index, /exports\.adminScheduleGiftDelivery = scheduledDelivery\.adminScheduleGiftDelivery/);
  assert.match(index, /exports\.adminScheduleHealthPlusDelivery/);
  assert.match(index, /exports\.activateDueScheduledDeliveries/);
  assert.match(source, /schedule\("every 1 minutes"\)/);
  assert.match(source, /timeZone\("Europe\/London"\)/);
});

test("client scheduled mutations require App Check and Admin role authority", () => {
  assert.match(source, /adminScheduleGiftDelivery = functions\.runWith\(\{enforceAppCheck: true\}\)/);
  assert.match(source, /adminScheduleHealthPlusDelivery = functions\.runWith\(\{enforceAppCheck: true\}\)/);
  assert.match(source, /getRiderScheduledJobs = functions\.runWith\(\{enforceAppCheck: true\}\)/);
  assert.match(source, /requireAdmin\(context/);
  assert.match(source, /requireAuth\(context\)/);
});

test("future scheduled work cannot leak into offer, dispatch, or acceptance paths", () => {
  assert.match(dispatch, /scheduledDelivery\.isOpenDispatchOffer/);
  assert.match(offers, /scheduledDelivery\.isOpenDispatchOffer/);
  assert.match(acceptance, /scheduledDelivery\.isOpenDispatchOffer/);
  assert.match(offers, /scheduled_not_active/);
  assert.match(acceptance, /scheduled_not_active/);
});

test("activation is idempotent and reserves busy state only at the window", () => {
  assert.match(source, /currentStatus !== "scheduled"/);
  assert.match(source, /reason: "already_activated"/);
  assert.match(source, /busy: true/);
  assert.match(source, /source: "scheduledDeliveryActivation"/);
  assert.match(source, /assertNoActiveDelivery/);
});

test("Rider Scheduled Jobs is backend projected and Rider isolated", () => {
  assert.match(source, /where\("assignedRiderId", "==", riderId\)/);
  assert.match(source, /job\.assignedRiderId === riderId/);
  assert.match(rider, /httpsCallable\('getRiderScheduledJobs'\)/);
  assert.match(rider, /title: 'Scheduled Jobs'/);
  assert.doesNotMatch(rider, /collection\('deliveryRequests'\)[\s\S]{0,160}where\('status', isEqualTo: 'scheduled'\)/);
});

test("scheduled and ready states restore into canonical Sender lifecycle meanings", () => {
  assert.match(tracking, /scheduled: SENDER_TRACKING_STATES\.FINDING_RIDER/);
  assert.match(tracking, /ready: SENDER_TRACKING_STATES\.RIDER_ASSIGNED/);
  assert.match(tracking, /ready: \["navigating_to_pickup"/);
});

test("clients cannot forge strategy, schedule, or Rider assignment fields", () => {
  for (const field of [
    "dispatchStatus", "matchingStatus", "fulfilmentMode", "fulfilmentStrategy",
    "scheduledAt", "scheduleActivatedAt", "riderId", "assignedRiderId",
  ]) {
    assert.match(rules, new RegExp(`'${field}'`));
  }
});

test("Gift reservation is explicit while competitive scheduling remains the default", () => {
  assert.match(source, /riderReservationMode: riderId \? "admin_reserved" : "competitive_at_activation"/);
  assert.match(source, /offerMode: riderId \? "admin_reserved" : "competitive_at_activation"/);
  assert.match(source, /gift_delivery_scheduled_competitive/);
});
