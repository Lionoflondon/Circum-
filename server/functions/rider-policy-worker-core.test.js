"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {createProcessor, semanticHash, validateJob} = require("./rider-policy-worker-core");

function fakeDb(presence = {}) {
  return {collection: () => ({doc: () => ({get: async () => ({exists: true, data: () => presence})})})};
}

test("worker accepts only minimal bounded identity data", () => {
  assert.equal(validateJob({riderId: "qa-rider", cause: "admin.suspend", correlationId: "op-1"}).riderId, "qa-rider");
  assert.throws(() => validateJob({riderId: "../../bad"}), /invalid_rider_id/);
  assert.throws(() => validateJob({riderId: "ok", cause: "bad cause"}), /invalid_cause/);
});

test("one thousand duplicate requests remain semantic no-ops", async () => {
  let calls = 0;
  const logs = [];
  const processor = createProcessor({
    db: fakeDb({onlineIntent: true, dispatchEligible: false}),
    applyRiderOperationalState: async () => {
      calls++;
      return {changed: false, state: {onlineIntent: true, dispatchEligible: false}};
    },
    logger: {info: (x) => logs.push(JSON.parse(x))},
  });
  const results = await Promise.all(Array.from({length: 1000}, (_, i) => processor({riderId: "qa-rider", cause: "duplicate", correlationId: `dup-${i}`})));
  assert.equal(calls, 1000);
  assert.equal(results.filter((x) => x.outcome === "NO_OP").length, 1000);
  assert.equal(logs.every((x) => x.changedFields.length === 0), true);
});

test("one hundred transitions have linear effects", async () => {
  let writes = 0;
  const processor = createProcessor({db: fakeDb({}), applyRiderOperationalState: async () => ({changed: Boolean(++writes), fields: ["dispatchEligible"], state: {dispatchEligible: true}}), logger: {info: () => {}}});
  await Promise.all(Array.from({length: 100}, (_, i) => processor({riderId: `qa-${i}`, cause: "transition", correlationId: `linear-${i}`})));
  assert.equal(writes, 100);
});

test("semantic hashes ignore timestamps and sensitive profile data", () => {
  assert.equal(semanticHash({dispatchEligible: false, updatedAt: 1, email: "a@example.test"}), semanticHash({dispatchEligible: false, updatedAt: 2, email: "b@example.test"}));
});
