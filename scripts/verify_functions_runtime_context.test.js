"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {missingRuntimeProjectContext, needsRuntimeProjectContext} =
  require("./verify_functions_runtime_context");

test("scheduled and event Functions require GCLOUD_PROJECT", () => {
  assert.equal(needsRuntimeProjectContext({scheduleTrigger: {schedule: "every 5 minutes"}}), true);
  assert.equal(needsRuntimeProjectContext({trigger: {eventType: "firestore.document.write"}}), true);
  assert.deepEqual(missingRuntimeProjectContext([
    {id: "scheduled", scheduleTrigger: {}, environmentVariables: {}},
    {id: "event", trigger: {eventType: "firestore.document.write"}, environmentVariables: {}},
    {id: "healthy", trigger: {eventType: "firestore.document.create"}, environmentVariables: {GCLOUD_PROJECT: "project"}},
    {id: "callable", environmentVariables: {}},
  ]), ["event", "scheduled"]);
});

test("healthy scheduled and event Functions pass the runtime contract", () => {
  assert.deepEqual(missingRuntimeProjectContext([
    {id: "scheduled", schedule: "every day", environmentVariables: {GCLOUD_PROJECT: "project"}},
    {id: "event", eventTrigger: {eventType: "storage.object.finalize"}, environmentVariables: {GCLOUD_PROJECT: "project"}},
  ]), []);
});
