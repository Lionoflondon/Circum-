"use strict";

const http = require("node:http");

function json(res, status, body) {
  res.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-store",
  });
  res.end(JSON.stringify(body));
}

function schedulerHeaderMatches(value, expected) {
  const actual = String(value || "");
  if (!actual) return false;
  return actual === expected || actual.endsWith(`/jobs/${expected}`);
}

function createSenderCancellationReconcilerServer(reconcile) {
  if (typeof reconcile !== "function") throw new TypeError("reconcile is required");
  return http.createServer(async (req, res) => {
    if (req.method === "GET" && req.url === "/healthz") {
      return json(res, 200, {
        status: "ok",
        service: "sender-cancellation-reconciler",
        runtime: "node22",
        mode: String(process.env.STRIPE_MODE || "").toLowerCase(),
        source: process.env.CIRCUM_SOURCE_SHA || "unknown",
      });
    }
    if (req.method !== "POST" || req.url !== "/run") {
      return json(res, 404, {error: "not_found"});
    }
    const expectedJob = String(process.env.SCHEDULER_JOB_NAME || "");
    if (!schedulerHeaderMatches(req.headers["x-cloudscheduler-jobname"], expectedJob)) {
      return json(res, 403, {error: "scheduler_identity_required"});
    }
    try {
      const result = await reconcile({});
      return json(res, 200, {ok: true, result});
    } catch (error) {
      console.error("sender_cancellation_reconciliation_failed", {
        reason: error && error.message ? error.message : "internal_error",
      });
      return json(res, 500, {error: "reconciliation_failed"});
    }
  });
}

if (require.main === module) {
  const reconciler = require("./index").reconcilePendingSenderCancellations;
  const port = Number(process.env.PORT || 8080);
  createSenderCancellationReconcilerServer((context) => reconciler.run(context))
      .listen(port, "0.0.0.0");
}

module.exports = {createSenderCancellationReconcilerServer, schedulerHeaderMatches};
