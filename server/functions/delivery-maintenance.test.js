"use strict";
const {test} = require("node:test");
const assert = require("node:assert/strict");
const {parseTick} = require("./delivery-maintenance-http");
const {watchdogCondition, THRESHOLDS, distanceMeters} = require("./delivery-maintenance-core");
const worker = "activateDueScheduledDeliveries";
const now = Date.now();
const tick = () => ({subscription: `projects/circum-2797c/subscriptions/gcf-${worker}-us-central1-firebase-schedule-${worker}-us-central1`, message: {messageId: "100", publishTime: new Date(now - 6 * 86400000).toISOString(), attributes: {scheduled: "true"}}});
test("historical empty Scheduler ticks are inspected without applying historical business time", () => {
 assert.equal(parseTick(worker, tick(), now).ageSeconds, 6 * 86400);
});
test("wrong subscription, customer commands and future messages never enter a worker", () => {
 for (const patch of [{subscription: "different"}, {message: {...tick().message, data: Buffer.from("{\"deliveryId\":\"customer\"}").toString("base64")}}, {message: {...tick().message, publishTime: new Date(now + 120000).toISOString()}}, {message: {...tick().message, attributes: {scheduled: "false"}}}]) assert.throws(() => parseTick(worker, {...tick(), ...patch}, now));
});
test("reconciled watchdog policy excludes terminal states and keeps original thresholds", () => {
 assert.equal(watchdogCondition({status: "completed", riderId: "rider"}), null);
 assert.equal(watchdogCondition({status: "accepted", riderId: "rider"}), "accepted_no_movement");
 assert.equal(watchdogCondition({status: "requested", paymentStatus: "paid"}), "payment_dispatch_failure");
 assert.equal(THRESHOLDS.collected_no_movement, 10);
 assert.ok(distanceMeters({latitude: 51, longitude: 0}, {latitude: 51.01, longitude: 0}) > 100);
});
