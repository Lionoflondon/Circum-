"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {createServer} = require("./cloud-run-rider-policy-server");
const {DocumentEventData, EVENT_TYPE} = require("./rider-policy-firestore-event");

function encodedEvent(before, after, paths) {
  const name = "projects/circum-2797c/databases/(default)/documents/riderProfiles/qa-rider";
  return Buffer.from(DocumentEventData.encode(DocumentEventData.fromObject({
    oldValue: {name, fields: before},
    value: {name, fields: after},
    updateMask: {paths},
  })).finish());
}

async function withServer(run) {
  const server = createServer({processorFactory: () => async (body) => ({outcome: "NO_OP", riderId: body.riderId})});
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
    await run(`http://127.0.0.1:${server.address().port}`);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

test("health and recompute transport are bounded", async () => withServer(async (url) => {
  let response = await fetch(`${url}/health`);
  assert.equal(response.status, 200);
  response = await fetch(`${url}/v1/recompute`, {method: "POST", headers: {"content-type": "application/json"}, body: JSON.stringify({riderId: "qa-rider"})});
  assert.equal(response.status, 200);
  assert.equal((await response.json()).outcome, "NO_OP");
  response = await fetch(`${url}/v1/recompute`, {method: "POST", headers: {"content-type": "application/json"}, body: "x".repeat(17000)});
  assert.equal(response.status, 413);
}));

test("Eventarc adapter applies relevant policy and ignores metadata-only changes", async () => {
  let applications = 0;
  const server = createServer({processorFactory: () => async (job) => ({outcome: ++applications === 1 ? "APPLIED" : "NO_OP", ...job})});
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const url = `http://127.0.0.1:${server.address().port}/v1/events/firestore/rider-profile`;
  const headers = {"content-type": "application/protobuf", "ce-type": EVENT_TYPE, "ce-id": "policy-1", "ce-document": "riderProfiles/qa-rider"};
  try {
    let response = await fetch(url, {method: "POST", headers, body: encodedEvent({approvalStatus: {stringValue: "pending"}}, {approvalStatus: {stringValue: "approved"}}, ["approvalStatus"])});
    assert.equal(response.status, 200);
    assert.equal((await response.json()).outcome, "APPLIED");
    response = await fetch(url, {method: "POST", headers: {...headers, "ce-id": "metadata-1"}, body: encodedEvent({updatedAt: {stringValue: "before"}}, {updatedAt: {stringValue: "after"}}, ["updatedAt"])});
    assert.equal(response.status, 200);
    assert.equal((await response.json()).outcome, "IGNORED");
    assert.equal(applications, 1);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test("one hundred duplicate Eventarc deliveries settle after one semantic application", async () => {
  let writes = 0;
  const server = createServer({processorFactory: () => async () => ({outcome: writes++ === 0 ? "APPLIED" : "NO_OP"})});
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const url = `http://127.0.0.1:${server.address().port}/v1/events/firestore/rider-profile`;
  const body = encodedEvent({isSuspended: {booleanValue: false}}, {isSuspended: {booleanValue: true}}, ["isSuspended"]);
  try {
    const results = await Promise.all(Array.from({length: 100}, (_, index) => fetch(url, {method: "POST", headers: {"content-type": "application/protobuf", "ce-type": EVENT_TYPE, "ce-id": `duplicate-${index}`, "ce-document": "riderProfiles/qa-rider"}, body}).then((response) => response.json())));
    assert.equal(results.filter((result) => result.outcome === "APPLIED").length, 1);
    assert.equal(results.filter((result) => result.outcome === "NO_OP").length, 99);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});
