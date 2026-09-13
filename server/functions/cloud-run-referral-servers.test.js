"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {createServer: createCallableServer} = require("./cloud-run-referral-callable-server");
const {createServer: createEventServer} = require("./cloud-run-referral-events-server");
const {DocumentEventData, EVENT_TYPE} = require("./rider-policy-firestore-event");

async function listen(server, run) {
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
    await run(`http://127.0.0.1:${server.address().port}`);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

test("callable adapter requires Firebase auth and preserves denied activation", async () => {
  const calls = [];
  const server = createCallableServer({dependenciesFactory: () => ({
    verifyIdToken: async (token) => token === "valid" ? {uid: "sender-1", email: "sender@example.invalid"} : Promise.reject(new Error("bad token")),
    handlers: {
      ensureReferralCode: async (_data, context) => (calls.push(context.auth.uid), {referralCode: "CODE1"}),
      attachReferralCode: async () => ({status: "applied"}),
      activateReferral: async () => {
 throw Object.assign(new Error("Backend only."), {code: "permission-denied"});
},
    },
  })});
  await listen(server, async (url) => {
    let response = await fetch(`${url}/v1/callable/ensureReferralCode`, {method: "POST", headers: {"content-type": "application/json"}, body: JSON.stringify({data: {}})});
    assert.equal(response.status, 401);
    response = await fetch(`${url}/v1/callable/ensureReferralCode`, {method: "POST", headers: {authorization: "Bearer valid", "content-type": "application/json"}, body: JSON.stringify({data: {}})});
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {result: {referralCode: "CODE1"}});
    response = await fetch(`${url}/v1/callable/activateReferral`, {method: "POST", headers: {authorization: "Bearer valid", "content-type": "application/json"}, body: JSON.stringify({data: {}})});
    assert.equal(response.status, 403);
    assert.equal(calls.length, 1);
  });
});

function encodedEvent(collection, id, before, after) {
  const name = `projects/circum-2797c/databases/(default)/documents/${collection}/${id}`;
  return Buffer.from(DocumentEventData.encode(DocumentEventData.fromObject({oldValue: {name, fields: before}, value: {name, fields: after}, updateMask: {paths: ["status"]}})).finish());
}

test("private event adapter routes each completion once and ignores non-terminal updates", async () => {
  const calls = [];
  const server = createEventServer({handlersFactory: () => ({
    becameCompleted: (before, after) => before.status !== "completed" && after.status === "completed",
    handleDeliveryCompletedReferral: async (value) => (calls.push(["delivery", value.deliveryId]), {status: "ROTH_AWARDED"}),
    handleGiftCompletedReferral: async (value) => (calls.push(["gift", value.giftId]), {status: "ROTH_AWARDED"}),
    handleHealthPlusCompletedReferral: async (value) => (calls.push(["health", value.pickupId]), {status: "ROTH_AWARDED"}),
  })});
  await listen(server, async (url) => {
    const request = (collection, id, before, after, eventId) => fetch(`${url}/v1/events/firestore/referral-completion`, {method: "POST", headers: {"content-type": "application/protobuf", "ce-type": EVENT_TYPE, "ce-id": eventId, "ce-document": `${collection}/${id}`}, body: encodedEvent(collection, id, before, after)});
    let response = await request("deliveryRequests", "delivery-1", {status: {stringValue: "pending"}}, {status: {stringValue: "completed"}, senderId: {stringValue: "sender-1"}}, "event-1");
    assert.equal(response.status, 200);
    response = await request("giftRequests", "gift-1", {status: {stringValue: "completed"}}, {status: {stringValue: "completed"}}, "event-2");
    assert.equal((await response.json()).outcome, "IGNORED");
    assert.deepEqual(calls, [["delivery", "delivery-1"]]);
  });
});

test("health endpoints start without Firebase or secret access", async () => {
  for (const server of [createCallableServer({dependenciesFactory: () => {
 throw new Error("must stay lazy");
}}), createEventServer({handlersFactory: () => {
 throw new Error("must stay lazy");
}})]) {
    await listen(server, async (url) => assert.equal((await fetch(`${url}/health`)).status, 200));
  }
});
