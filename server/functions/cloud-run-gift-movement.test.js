/* eslint-disable max-len */
"use strict";

const {test} = require("node:test");
const assert = require("node:assert/strict");
const {DocumentEventData} = require("./rider-policy-firestore-event");
const {createServer, giftIdFromName, eventTarget} = require("./cloud-run-gift-movement");

test("gift movement route accepts only matching Firestore paths", () => {
  assert.equal(giftIdFromName("projects/p/databases/(default)/documents/giftRequests/g1"), "g1");
  assert.equal(giftIdFromName("documents/deliveryRequests/g1"), null);
  assert.equal(giftIdFromName("documents/giftRequests/g1/nested"), null);
});

test("fixture event path requires the exact enabled fixture and remains nested", () => {
  const root = {collection: (name) => ({doc: (id) => ({collection: (child) => ({path: `${name}/${id}/${child}`})})}),
    runTransaction: async () => {}};
  const fixtureName = "documents/giftMovementRuntimeFixtures/__codex_gift_movement_canary/giftRequests/__codex_gift_1";
  const target = eventTarget(fixtureName, root, "__codex_gift_movement_canary");
  assert.equal(target.giftId, "__codex_gift_1");
  assert.equal(target.eventDb.collection("deliveryRequests").path,
      "giftMovementRuntimeFixtures/__codex_gift_movement_canary/deliveryRequests");
  assert.equal(eventTarget(fixtureName, root, "__codex_gift_movement_other"), null);
  assert.equal(eventTarget(fixtureName, root, ""), null);
});

test("health route works without invoking projection", async () => {
  const server = createServer({db: {}, project: async () => {
    throw new Error("unexpected projection");
  }});
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
    const base = `http://127.0.0.1:${server.address().port}`;
    assert.equal((await fetch(`${base}/healthz`)).status, 200);
    assert.equal((await fetch(`${base}/`, {method: "POST"})).status, 404);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test("created and updated Eventarc documents invoke the latest-source projector", async () => {
  const projected = [];
  const server = createServer({db: {}, project: async (_db, giftId) => {
    projected.push(giftId);
    return {status: "projected"};
  }});
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
    const base = `http://127.0.0.1:${server.address().port}`;
    const body = DocumentEventData.encode({value: {
      name: "projects/p/databases/(default)/documents/giftRequests/g1",
      fields: {status: {stringValue: "packed"}},
    }}).finish();
    for (const type of ["created", "updated"]) {
      const response = await fetch(`${base}/`, {method: "POST", headers: {
        "ce-type": `google.cloud.firestore.document.v1.${type}`,
        "ce-id": `${type}-event-1`,
      }, body});
      assert.equal(response.status, 200);
    }
    assert.deepEqual(projected, ["g1", "g1"]);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});
