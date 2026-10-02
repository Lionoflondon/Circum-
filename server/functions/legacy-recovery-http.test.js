/* eslint-disable max-len, require-jsdoc */
"use strict";
const test = require("node:test"); const assert = require("node:assert/strict"); const {parseTick} = require("./legacy-recovery-http");
function envelope(worker, message) {
return {subscription: `projects/circum-2797c/subscriptions/gcf-${worker}-us-central1-firebase-schedule-${worker}-us-central1`, message: {messageId: "123", publishTime: new Date().toISOString(), ...message}};
}
test("legacy Firebase scheduler metadata retains its empty heartbeat contract", () => {
  const worker = "processNoShowSettlementRetries"; assert.equal(parseTick(worker, envelope(worker, {attributes: {scheduled: "true"}})).messageId, "123");
  assert.throws(() => parseTick(worker, envelope(worker, {data: "e30="})), {statusCode: 400});
});
test("QA cleanup schedules retain their exact original JSON heartbeat without added attributes", () => {
  for (const worker of ["expireQaLifecycleFixtures", "expireQaSpecialFlowFixtures"]) {
    assert.equal(parseTick(worker, envelope(worker, {data: "e30="})).messageId, "123");
    assert.throws(() => parseTick(worker, envelope(worker, {attributes: {scheduled: "true"}, data: ""})), {statusCode: 400});
    assert.throws(() => parseTick(worker, envelope(worker, {data: "eyJwYXltZW50IjoxfQ=="})), {statusCode: 400});
  }
});
test("scheduler identity and timestamps cannot cross subscriptions or claim future work", () => {
  const worker = "reconcileStaleDeliveryLocks"; const body = envelope(worker, {attributes: {scheduled: "true"}});
  assert.throws(() => parseTick(worker, {...body, subscription: "projects/other/subscriptions/other"}), {statusCode: 400});
  assert.throws(() => parseTick(worker, {...body, message: {...body.message, publishTime: new Date(Date.now() + 120000).toISOString()}}), {statusCode: 400});
});
