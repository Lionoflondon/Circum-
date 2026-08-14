/* eslint-disable require-jsdoc */

async function checkAndConsumeRateLimit({
  db,
  key,
  max = 20,
  windowSeconds = 60,
  nowMs = Date.now(),
}) {
  if (!db || !key) throw new Error("Rate limit storage is required.");
  const ref = db.collection("rateLimits").doc(key);
  let result;
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    const current = snapshot.exists ? snapshot.data() : {};
    const storedWindowStart = Number(current.windowStartMs);
    const windowStart = Number.isFinite(storedWindowStart) ? storedWindowStart : nowMs;
    const inWindow = nowMs - windowStart < windowSeconds * 1000;
    const count = inWindow ? Number(current.count) || 0 : 0;
    const allowed = count < max;
    transaction.set(ref, {
      count: allowed ? count + 1 : count,
      windowStartMs: inWindow ? windowStart : nowMs,
      updatedAtMs: nowMs,
    }, {merge: true});
    result = {allowed, remaining: Math.max(0, max - count - (allowed ? 1 : 0))};
  });
  return result;
}

module.exports = {checkAndConsumeRateLimit};
