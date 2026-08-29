"use strict";

// Observability is synchronous and fail-open; it cannot affect authority.
function timing(stage, fields = {}) {
  try {
    console.info("circum_latency", {stage, at: new Date().toISOString(), ...fields});
  } catch (_) {
    // Logging failure must not affect the user operation.
  }
}

function elapsed(startedAt) {
  return Math.max(0, Number(process.hrtime.bigint() - startedAt) / 1e6);
}

function start(stage, fields = {}) {
  const startedAt = process.hrtime.bigint();
  timing(`${stage}_START`, fields);
  return (result = {}) => timing(`${stage}_COMPLETE`, {
    ...fields,
    ...result,
    durationMs: elapsed(startedAt),
  });
}

module.exports = {timing, start};
