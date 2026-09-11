/* eslint-disable max-len, require-jsdoc */
"use strict";

const crypto = require("node:crypto");

const RIDER_ID = /^[A-Za-z0-9_-]{1,128}$/;
const CAUSE = /^[A-Za-z0-9_.:-]{1,96}$/;

function semanticState(value = {}) {
  const keys = ["onlineIntent", "isOnline", "shouldForceOffline", "dispatchEligible", "dispatchReason", "presenceState", "connectionStatus", "availabilityStatus", "busy"];
  return Object.fromEntries(keys.filter((key) => value[key] !== undefined).map((key) => [key, value[key]]));
}

function semanticHash(value) {
  return crypto.createHash("sha256").update(JSON.stringify(semanticState(value))).digest("hex").slice(0, 16);
}

function validateJob(input = {}) {
  const riderId = String(input.riderId || "").trim();
  const cause = String(input.cause || "policyRecompute").trim();
  const correlationId = String(input.correlationId || crypto.randomUUID()).trim();
  if (!RIDER_ID.test(riderId)) throw Object.assign(new Error("invalid_rider_id"), {statusCode: 400});
  if (!CAUSE.test(cause)) throw Object.assign(new Error("invalid_cause"), {statusCode: 400});
  if (!correlationId || correlationId.length > 128) throw Object.assign(new Error("invalid_correlation_id"), {statusCode: 400});
  return {riderId, cause, correlationId};
}

function createProcessor({db, applyRiderOperationalState, logger = console}) {
  if (!db || typeof applyRiderOperationalState !== "function") throw new Error("worker_dependencies_required");
  return async function process(input) {
    const job = validateJob(input);
    const beforeSnapshot = await db.collection("riderPresence").doc(job.riderId).get();
    const before = beforeSnapshot.exists ? beforeSnapshot.data() || {} : {};
    const result = await applyRiderOperationalState(job.riderId, `cloudRun:${job.cause}`, db);
    const record = {
      event: "rider_policy_recompute",
      riderId: job.riderId,
      cause: job.cause,
      correlationId: job.correlationId,
      outcome: result.changed ? "APPLIED" : "NO_OP",
      oldSemanticHash: semanticHash(before),
      newSemanticHash: semanticHash(result.state || before),
      changedFields: result.fields || [],
    };
    logger.info(record);
    return {...record, state: semanticState(result.state || before)};
  };
}

module.exports = {createProcessor, semanticHash, semanticState, validateJob};
