"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {DocumentEventData} = require("./lib/eventarc-envelope");
const {createServer} = require("./cloud-run-rider-availability-server");

function eventBody() {
  const name = "projects/circum-2797c/databases/(default)/documents/riderProfiles/qa-rider";
  return Buffer.from(DocumentEventData.encode(DocumentEventData.fromObject({oldValue: {name, fields: {approvalStatus: {stringValue: "pending"}}}, value: {name, fields: {approvalStatus: {stringValue: "approved"}}}, updateMask: {paths: ["approvalStatus"]}})).finish());
}
async function withServer(run) {
  const server = createServer({processorFactory: () => async (event) => ({outcome: "APPLIED", riderId: event.riderId, changedFields: ["dispatchEligible"]})});
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
 await run(`http://127.0.0.1:${server.address().port}`);
} finally {
 await new Promise((resolve) => server.close(resolve));
}
}

test("health and Eventarc availability routes are bounded", async () => withServer(async (url) => {
  assert.equal((await fetch(`${url}/health`)).status, 200);
  let response = await fetch(`${url}/v1/events/firestore/rider-profile`, {method: "POST", headers: {"content-type": "application/protobuf", "ce-type": "google.cloud.firestore.document.v1.updated", "ce-id": "availability-http-1", "ce-document": "riderProfiles/qa-rider"}, body: eventBody()});
  assert.equal(response.status, 200);
  assert.equal((await response.json()).outcome, "APPLIED");
  const pubsubBody = JSON.stringify({message: {data: Buffer.from(JSON.stringify({data_base64: eventBody().toString("base64")})).toString("base64")}});
  response = await fetch(`${url}/v1/events/firestore/rider-profile`, {method: "POST", headers: {"content-type": "application/json", "ce-type": "google.cloud.firestore.document.v1.updated", "ce-id": "availability-http-2", "ce-document": "riderProfiles/qa-rider"}, body: pubsubBody});
  assert.equal(response.status, 200);
  assert.equal((await response.json()).outcome, "APPLIED");
  assert.equal((await fetch(`${url}/v1/events/firestore/rider-profile`, {method: "POST", headers: {"content-type": "text/plain"}, body: "x"})).status, 415);
}));

test("fixture route stays isolated from the production processor", async () => {
  const fixtureName = "projects/circum-2797c/databases/(default)/documents/_runtimeFixtures/riderAvailability/events/cert-http";
  const fixtureBody = Buffer.from(DocumentEventData.encode(DocumentEventData.fromObject({oldValue: {name: fixtureName, fields: {approvalStatus: {stringValue: "pending"}}}, value: {name: fixtureName, fields: {approvalStatus: {stringValue: "approved"}}}, updateMask: {paths: ["approvalStatus"]}})).finish());
  let productionCalls = 0;
  let fixtureCalls = 0;
  const server = createServer({
    processorFactory: () => async () => {
 productionCalls += 1; return {outcome: "APPLIED"};
},
    fixtureProcessorFactory: () => async (event) => {
 fixtureCalls += 1; return {outcome: "CERTIFIED", fixtureId: event.fixtureId};
},
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
    const response = await fetch(`http://127.0.0.1:${server.address().port}/v1/events/firestore/runtime-fixture`, {method: "POST", headers: {"content-type": "application/protobuf", "ce-type": "google.cloud.firestore.document.v1.updated", "ce-id": "fixture-http-1", "ce-document": "_runtimeFixtures/riderAvailability/events/cert-http"}, body: fixtureBody});
    assert.equal(response.status, 200);
    assert.equal((await response.json()).outcome, "CERTIFIED");
    assert.equal(fixtureCalls, 1);
    assert.equal(productionCalls, 0);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});
