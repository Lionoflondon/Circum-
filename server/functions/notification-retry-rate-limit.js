"use strict";

const LIMIT = 10;
const WINDOW_MS = 60000;

// Count attempted device deliveries, including failed/uncertain sends. A
// transaction makes the limit shared across workers and process restarts.
async function reserveRetryDeliveries(db, count, clock = Date.now) {
  if (!Number.isInteger(count) || count < 1 || count > LIMIT) {
    return {allowed: false, oversized: true};
  }
  const ref = db.collection("operationsState").doc("notification_retry_rate_limit_v1");
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const now = clock();
    const stored = snap.exists ? snap.data().attemptTimes : [];
    // Corrupt state must stop sends, rather than reset the budget.
    if (!Array.isArray(stored) || stored.some((n) => !Number.isFinite(n)) || stored.length > LIMIT) {
      throw new Error("notification_retry_rate_limit_invalid");
    }
    const active = stored.filter((n) => n > now - WINDOW_MS).sort((a, b) => a - b);
    if (active.length + count > LIMIT) {
      return {allowed: false, retryAt: active[active.length + count - LIMIT - 1] + WINDOW_MS};
    }
    tx.set(ref, {attemptTimes: [...active, ...Array(count).fill(now)], limit: LIMIT, windowMs: WINDOW_MS});
    return {allowed: true};
  });
}

module.exports = {reserveRetryDeliveries, LIMIT, WINDOW_MS};
