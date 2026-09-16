"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const http = require("node:http");
const {createSenderCancellationReconcilerServer, schedulerHeaderMatches} = require("./cloud-run-sender-cancellation-reconciler");

function request(port, options = {}) {
  return new Promise((resolve, reject) => {
    const req = http.request({port, method: "GET", ...options}, (res) => {
      let body = "";
      res.on("data", (chunk) => body += chunk);
      res.on("end", () => resolve({status: res.statusCode, body: JSON.parse(body)}));
    });
    req.on("error", reject);
    req.end();
  });
}

test("scheduler identity accepts the configured job and full resource name", () => {
  assert.equal(schedulerHeaderMatches("circum-sender-cancellation-reconciler", "circum-sender-cancellation-reconciler"), true);
  assert.equal(schedulerHeaderMatches("projects/p/locations/l/jobs/circum-sender-cancellation-reconciler", "circum-sender-cancellation-reconciler"), true);
  assert.equal(schedulerHeaderMatches("other-job", "circum-sender-cancellation-reconciler"), false);
});

test("reconciler exposes health without running the job", async () => {
  let runs = 0;
  const server = createSenderCancellationReconcilerServer(async () => {
    runs += 1;
    return {processed: 0};
  }).listen(0);
  const port = server.address().port;
  const response = await request(port, {path: "/healthz"});
  server.close();
  assert.deepEqual(response.body, {
    status: "ok",
    service: "sender-cancellation-reconciler",
    runtime: "node22",
    mode: "",
    source: "unknown",
  });
  assert.equal(runs, 0);
});

test("reconciler requires the configured Cloud Scheduler identity", async () => {
  const prior = process.env.SCHEDULER_JOB_NAME;
  process.env.SCHEDULER_JOB_NAME = "circum-sender-cancellation-reconciler";
  let runs = 0;
  const server = createSenderCancellationReconcilerServer(async () => {
    runs += 1;
    return {processed: 0};
  }).listen(0);
  const port = server.address().port;
  const denied = await request(port, {method: "POST", path: "/run"});
  const accepted = await request(port, {
    method: "POST",
    path: "/run",
    headers: {"x-cloudscheduler-jobname": "projects/p/locations/l/jobs/circum-sender-cancellation-reconciler"},
  });
  server.close();
  if (prior === undefined) delete process.env.SCHEDULER_JOB_NAME;
  else process.env.SCHEDULER_JOB_NAME = prior;
  assert.equal(denied.status, 403);
  assert.equal(accepted.status, 200);
  assert.deepEqual(accepted.body, {ok: true, result: {processed: 0}});
  assert.equal(runs, 1);
});

test("reconciler returns a safe failure without claiming completion", async () => {
  const prior = process.env.SCHEDULER_JOB_NAME;
  process.env.SCHEDULER_JOB_NAME = "circum-sender-cancellation-reconciler";
  const server = createSenderCancellationReconcilerServer(async () => {
    throw new Error("controlled failure");
  }).listen(0);
  const response = await request(server.address().port, {
    method: "POST",
    path: "/run",
    headers: {"x-cloudscheduler-jobname": "circum-sender-cancellation-reconciler"},
  });
  server.close();
  if (prior === undefined) delete process.env.SCHEDULER_JOB_NAME;
  else process.env.SCHEDULER_JOB_NAME = prior;
  assert.equal(response.status, 500);
  assert.deepEqual(response.body, {error: "reconciliation_failed"});
});
