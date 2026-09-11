"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const dispatch = require("./rider-policy-dispatch");

function client(createTask) {
  return {queuePath: (...x) => x.join("/"), taskPath: (...x) => x.join("/"), createTask};
}

test("queue request is private, minimal and deterministic", async () => {
  let request;
  const result = await dispatch.enqueueRiderPolicyRecompute({riderId: "rider-1", cause: "admin.suspend", correlationId: "audit-1"}, {client: client(async (value) => {
    request = value;
    return [{name: value.task.name}];
  })});
  const body = JSON.parse(Buffer.from(request.task.httpRequest.body, "base64").toString("utf8"));
  assert.deepEqual(body, {riderId: "rider-1", cause: "admin.suspend", correlationId: "audit-1"});
  assert.equal(request.task.httpRequest.oidcToken.serviceAccountEmail, dispatch._config.INVOKER);
  assert.equal(result.queued, true);
});

test("duplicate task identity settles successfully", async () => {
  const fake = client(async () => {
    const error = new Error("ALREADY_EXISTS");
    error.code = 6;
    throw error;
  });
  const result = await dispatch.enqueueRiderPolicyRecompute({riderId: "rider-1", cause: "admin.approve", correlationId: "audit-1"}, {client: fake});
  assert.equal(result.duplicate, true);
});

test("task identity is stable and operation-specific", () => {
  assert.equal(dispatch.taskId("rider-1", "audit-1"), dispatch.taskId("rider-1", "audit-1"));
  assert.notEqual(dispatch.taskId("rider-1", "audit-1"), dispatch.taskId("rider-1", "audit-2"));
});
