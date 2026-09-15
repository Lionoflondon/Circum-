"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {claimId, processAvailabilityEvent} = require("./rider-availability-worker-core");

function fakeDb(seed = {}) {
  const docs = new Map(Object.entries(seed));
  const writes = [];
  const ref = (path) => ({path, collection: (name) => ({doc: (id) => ref(`${path}/${name}/${id}`)})});
  let transactionTail = Promise.resolve();
  const db = {
    collection: (name) => ({doc: (id) => ref(`${name}/${id}`)}),
    runTransaction: (run) => {
      const next = transactionTail.then(() => run({
        get: async (target) => ({exists: docs.has(target.path), data: () => docs.get(target.path)}),
        set: (target, value) => {
docs.set(target.path, {...(docs.get(target.path) || {}), ...value}); writes.push({kind: "set", path: target.path, value});
},
        create: (target, value) => {
if (docs.has(target.path)) throw new Error("already_exists"); docs.set(target.path, value); writes.push({kind: "create", path: target.path, value});
},
      }));
      transactionTail = next.catch(() => {});
      return next;
    },
  };
  return {db, docs, writes};
}
const fieldValue = {serverTimestamp: () => "SERVER_TIME"};
const event = {eventId: "availability-event-1", riderId: "qa-rider", sourceCollection: "riderProfiles"};

test("blocked rider is forced offline once and identical Eventarc replay is a no-op", async () => {
  const {db, docs, writes} = fakeDb({
    "riders/qa-rider": {approvalStatus: "approved", vehicleApproved: true, dispatchEligible: true},
    "riderProfiles/qa-rider": {accountStatus: "suspended"},
    "riderPresence/qa-rider": {isOnline: true, onlineIntent: true, availabilityStatus: "available", busy: false},
  });
  const first = await processAvailabilityEvent({db, event, fieldValue});
  assert.equal(first.outcome, "APPLIED");
  assert.equal(docs.get("riderPresence/qa-rider").isOnline, false);
  assert.equal(docs.get("riderPresence/qa-rider").dispatchReason, "account_blocked");
  assert.equal(writes.filter((write) => write.path === "riders/qa-rider" || write.path === "riderProfiles/qa-rider").length, 0);
  const writeCount = writes.length;
  const replay = await processAvailabilityEvent({db, event, fieldValue});
  assert.equal(replay.outcome, "DUPLICATE");
  assert.equal(writes.length, writeCount);
  assert.equal(docs.has(`eventHandlerClaims/${claimId(event)}`), true);
});

test("one hundred duplicate deliveries create one claim and one bounded state update", async () => {
  const {db, writes} = fakeDb({
    "riders/qa-rider": {approvalStatus: "approved", vehicleApproved: true},
    "riderProfiles/qa-rider": {approvalStatus: "approved", vehicleApproved: true},
    "riderPresence/qa-rider": {isOnline: false, onlineIntent: false, availabilityStatus: "offline"},
  });
  const results = await Promise.all(Array.from({length: 100}, () => processAvailabilityEvent({db, event, fieldValue})));
  assert.equal(results.filter((result) => result.outcome === "DUPLICATE").length, 99);
  assert.equal(writes.filter((write) => write.kind === "create").length, 1);
  assert.ok(writes.filter((write) => write.kind === "set").length <= 1);
});

test("fixture certification is confined to fixture claims and is concurrency safe", async () => {
  const {processFixtureAvailabilityEvent, fixtureClaimId} = require("./rider-availability-worker-core");
  const fixtureEvent = {eventId: "fixture-event-20", fixtureId: "cert-20", sourceCollection: "_runtimeFixtures", fixture: true, changedFields: ["approvalStatus"]};
  const {db, docs, writes} = fakeDb();
  const results = await Promise.all(Array.from({length: 20}, () => processFixtureAvailabilityEvent({db, event: fixtureEvent, fieldValue})));
  assert.equal(results.filter((result) => result.outcome === "CERTIFIED").length, 1);
  assert.equal(results.filter((result) => result.outcome === "DUPLICATE").length, 19);
  assert.equal(writes.length, 1);
  assert.equal(writes[0].path, `_runtimeFixtures/riderAvailability/claims/${fixtureClaimId(fixtureEvent)}`);
  assert.equal(docs.has(`_runtimeFixtures/riderAvailability/claims/${fixtureClaimId(fixtureEvent)}`), true);
  assert.equal(writes.some((write) => /^(riderProfiles|riders|riderPresence|eventHandlerClaims)\//.test(write.path)), false);
});
