/* eslint-disable max-len, require-jsdoc */
"use strict";

const crypto = require("node:crypto");
const {CloudTasksClient} = require("@google-cloud/tasks");

const PROJECT = "circum-2797c";
const LOCATION = "us-central1";
const QUEUE = "rider-policy-recompute";
const WORKER_URL = "https://circum-rider-policy-worker-j2b7cicfwq-uc.a.run.app/v1/recompute";
const INVOKER = "rider-policy-invoker@circum-2797c.iam.gserviceaccount.com";

let client;
function tasksClient() {
  if (!client) client = new CloudTasksClient();
  return client;
}

function taskId(riderId, correlationId) {
  return `rider-policy-${crypto.createHash("sha256").update(`${riderId}:${correlationId}`).digest("hex").slice(0, 40)}`;
}

async function enqueueRiderPolicyRecompute({riderId, cause, correlationId}, options = {}) {
  if (!riderId || !correlationId) throw new Error("rider_policy_identity_required");
  const activeClient = options.client || tasksClient();
  const parent = activeClient.queuePath(PROJECT, LOCATION, QUEUE);
  const name = activeClient.taskPath(PROJECT, LOCATION, QUEUE, taskId(riderId, correlationId));
  const payload = {riderId, cause, correlationId};
  try {
    const [task] = await activeClient.createTask({
      parent,
      task: {
        name,
        httpRequest: {
          httpMethod: "POST",
          url: WORKER_URL,
          headers: {"Content-Type": "application/json"},
          body: Buffer.from(JSON.stringify(payload)).toString("base64"),
          oidcToken: {serviceAccountEmail: INVOKER, audience: WORKER_URL.replace("/v1/recompute", "")},
        },
      },
    });
    return {queued: true, taskName: task.name || name};
  } catch (error) {
    if (Number(error.code) === 6 || String(error.message || "").includes("ALREADY_EXISTS")) {
      return {queued: true, duplicate: true, taskName: name};
    }
    throw error;
  }
}

module.exports = {enqueueRiderPolicyRecompute, taskId, _config: {PROJECT, LOCATION, QUEUE, WORKER_URL, INVOKER}};
