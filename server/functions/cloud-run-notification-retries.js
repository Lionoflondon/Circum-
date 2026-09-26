"use strict";

const http = require("node:http");
const {initializeApp, getApps} = require("firebase-admin/app");
const {processNotificationRetriesCore} = require("./notification-retry-core");

const TOPIC = "firebase-schedule-processNotificationRetries-us-central1";
if (!getApps().length) initializeApp();

function isRetryEvent(url = "", headers = {}) {
  const raw = String(url || "");
  const mode = new URL(raw || "/", "http://localhost").searchParams.get("__GCP_CloudEventsMode") || "";
  const match = /^CUSTOM_PUBSUB_projects\/[^/]+\/topics\/([^/?]+)$/.exec(mode);
  if (match) return match[1] === TOPIC;
  const source = String(headers["ce-source"] || headers["x-goog-cloud-event-source"] || "");
  return source.endsWith(`/topics/${TOPIC}`);
}

function createServer(run = processNotificationRetriesCore) {
  return http.createServer(async (req, res) => {
    const path = new URL(req.url, "http://localhost").pathname;
    if (req.method === "GET" && path === "/healthz") {
      res.writeHead(200, {"content-type": "application/json"});
      res.end(JSON.stringify({ok: true, service: "notification-retries", sourceSha: process.env.SOURCE_SHA || "unknown"}));
      return;
    }
    if (req.method === "POST" && path === "/dry-run") {
      try {
        const result = await run({dryRun: true});
        res.writeHead(200, {"content-type": "application/json"});
        res.end(JSON.stringify({ok: true, result}));
      } catch (_) {
        res.writeHead(500, {"content-type": "application/json"});
        res.end(JSON.stringify({ok: false}));
      }
      return;
    }
    if (req.method !== "POST" || path !== "/" || !isRetryEvent(req.url, req.headers)) {
      res.writeHead(404).end();
      return;
    }
    try {
      const result = await run();
      console.log("notification_retry_completed", result);
      res.writeHead(200, {"content-type": "application/json"});
      res.end(JSON.stringify({ok: true, result}));
    } catch (error) {
      console.error("notification_retry_failed", {code: String(error && error.code || "internal").slice(0, 120)});
      res.writeHead(500, {"content-type": "application/json"});
      res.end(JSON.stringify({ok: false}));
    }
  });
}

if (require.main === module) createServer().listen(Number(process.env.PORT || 8080), "0.0.0.0");
module.exports = {createServer, isRetryEvent};
