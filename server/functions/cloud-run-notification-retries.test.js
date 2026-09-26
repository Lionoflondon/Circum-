"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {once} = require("node:events");
const {createServer, isRetryEvent} = require("./cloud-run-notification-retries");

const topicUrl = "/?__GCP_CloudEventsMode=CUSTOM_PUBSUB_projects%2Fcircum-2797c%2Ftopics%2Ffirebase-schedule-processNotificationRetries-us-central1";

test("only the exact retry Scheduler topic is routable", () => {
  assert.equal(isRetryEvent(topicUrl), true);
  assert.equal(isRetryEvent("/", {"ce-source": "//pubsub.googleapis.com/projects/circum-2797c/topics/firebase-schedule-processNotificationRetries-us-central1"}), true);
  assert.equal(isRetryEvent("/?__GCP_CloudEventsMode=CUSTOM_PUBSUB_projects%2Fcircum-2797c%2Ftopics%2Fother"), false);
  assert.equal(isRetryEvent("/", {"ce-source": "//pubsub.googleapis.com/projects/circum-2797c/topics/other"}), false);
});

test("retry service returns bounded worker result and ignores other routes", async () => {
  let calls = 0;
  const server = createServer(async (options = {}) => {
    calls++;
    return options.dryRun ? {scanned: 0, due: 0, dryRun: true} : {scanned: 0, sent: 0};
  });
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  try {
    const url = `http://127.0.0.1:${server.address().port}`;
    assert.equal((await fetch(`${url}/healthz`)).status, 200);
    assert.equal((await fetch(`${url}/`, {method: "POST"})).status, 404);
    const preview = await fetch(`${url}/dry-run`, {method: "POST"});
    assert.deepEqual(await preview.json(), {ok: true, result: {scanned: 0, due: 0, dryRun: true}});
    const response = await fetch(`${url}${topicUrl}`, {method: "POST"});
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {ok: true, result: {scanned: 0, sent: 0}});
    assert.equal(calls, 2);
  } finally {
    server.close();
    await once(server, "close");
  }
});
