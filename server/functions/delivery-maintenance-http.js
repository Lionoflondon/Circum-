/* eslint-disable max-len, require-jsdoc */
"use strict";
const {randomUUID, createHash} = require("node:crypto");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {runWorker, WORKERS} = require("./delivery-maintenance-core");
const {fixtureDb, isFixtureDeliveryId} = require("./gift-story-fixture-db");
const INTERVALS = {activateDueScheduledDeliveries: 60000, escalateUnclaimedDeliveries: 60000, deliveryLifecycleWatchdog: 300000, markStaleRiderPresenceOffline: 120000};
function parseTick(worker, body, now = Date.now()) {
 const subscription = `projects/circum-2797c/subscriptions/gcf-${worker}-us-central1-firebase-schedule-${worker}-us-central1`;
 const message = body?.message;
 if (body?.subscription !== subscription || !message || message.attributes?.scheduled !== "true" || (message.data != null && message.data !== "") || !/^[A-Za-z0-9_-]{1,128}$/.test(message.messageId || "") || !Number.isFinite(Date.parse(message.publishTime)) || Date.parse(message.publishTime) > now + 60000) throw Object.assign(new Error("invalid_scheduler_tick"), {statusCode: 400});
 return {messageId: message.messageId, publishTime: message.publishTime, ageSeconds: Math.max(0, Math.floor((now - Date.parse(message.publishTime)) / 1000))};
}
async function processTick({db, worker, tick, now = Date.now(), run = runWorker}) {
 const controlRef = db.collection("deliveryWorkerControl").doc(worker);
 const leaseRef = db.collection("operationsState").doc(`delivery_worker_${worker}`);
 const receiptRef = db.collection("deliveryWorkerReceipts").doc(createHash("sha256").update(`${worker}:${tick.messageId}`).digest("hex"));
 const claimId = randomUUID();
 const claimed = await db.runTransaction(async (tx) => {
  const [control, lease, receipt] = await Promise.all([tx.get(controlRef), tx.get(leaseRef), tx.get(receiptRef)]);
  if (receipt.exists) return {replayed: true, result: receipt.data().result};
  const c = control.data() || {}; const l = lease.data() || {};
  const maximum = Number(c.maxAcknowledgements || 0); const acknowledged = Number(c.acknowledged || 0);
  const certifiedAt = typeof c.drainCertifiedAt?.toMillis === "function" ? c.drainCertifiedAt.toMillis() : 0;
  const steady = c.mode === "steady" && certifiedAt > 0 && certifiedAt <= now;
  if (c.enabled !== true || !Number.isSafeInteger(maximum) || maximum < 1 || !Number.isSafeInteger(acknowledged) || acknowledged < 0 || (c.mode === "steady" && !steady) || (!steady && acknowledged >= maximum)) throw Object.assign(new Error("bounded_cutover_paused"), {statusCode: 503});
  if (Number(l.leaseUntil || 0) > now) throw Object.assign(new Error("worker_busy"), {statusCode: 503});
  if (l.lastCompletedAt && now - l.lastCompletedAt < INTERVALS[worker]) {
   tx.create(receiptRef, {worker, publishTime: tick.publishTime, ageSeconds: tick.ageSeconds, result: {coalesced: true}, createdAt: FieldValue.serverTimestamp()});
   tx.set(controlRef, {acknowledged: FieldValue.increment(1)}, {merge: true}); return {replayed: true, result: {coalesced: true}};
  }
  tx.set(leaseRef, {claimId, leaseUntil: now + 120000}, {merge: true}); return {limit: Number(c.batchLimit || 5)};
 });
 if (claimed.replayed) return claimed.result;
 try {
  const result = await run({db, worker, now, limit: claimed.limit});
  await db.runTransaction(async (tx) => {
   const lease = await tx.get(leaseRef); if (lease.data()?.claimId !== claimId) throw new Error("worker_lease_lost");
   tx.create(receiptRef, {worker, publishTime: tick.publishTime, ageSeconds: tick.ageSeconds, result, createdAt: FieldValue.serverTimestamp()});
   tx.set(controlRef, {acknowledged: FieldValue.increment(1), lastResult: result, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
   tx.set(leaseRef, {leaseUntil: 0, lastCompletedAt: now, lastResult: result}, {merge: true});
  }); return result;
 } catch (error) {
  await db.runTransaction(async (tx) => {
const lease = await tx.get(leaseRef); if (lease.data()?.claimId === claimId) tx.set(leaseRef, {leaseUntil: 0}, {merge: true});
}); throw error;
 }
}
function handleMaintenance(req, res, allowedWorkers, options = {}) {
 const parts = new URL(req.url, "http://localhost").pathname.split("/");
 if (parts[1] !== "maintenance") return false;
 const send = (status, result) => {
res.writeHead(status, {"content-type": "application/json", "cache-control": "no-store"}); res.end(JSON.stringify(result));
};
 const worker = parts[2]; const mode = parts[3] || "tick";
 if (!allowedWorkers.includes(worker) || !WORKERS[worker]) {
send(404, {error: "not_found"}); return true;
}
 if (req.method !== "POST") {
send(405, {error: "method_not_allowed"}); return true;
}
 let size = 0; const chunks = [];
 req.on("data", (x) => {
size += x.length; if (size <= 16384) chunks.push(x);
});
 req.on("end", async () => {
  try {
   if (size > 16384) {
send(413, {error: "request_too_large"}); return;
}
   const input = JSON.parse(Buffer.concat(chunks).toString("utf8")); const rawDb = options.db || (options.dbFactory ? options.dbFactory() : getFirestore()); let result;
   if (mode === "fixture") {
    if (!isFixtureDeliveryId(input.fixtureId)) throw Object.assign(new Error("invalid_fixture_delivery_id"), {statusCode: 400});
    const root = await rawDb.collection("giftStoryRuntimeFixtures").doc(input.fixtureId).get();
    if (!root.exists || root.data().purpose !== "delivery_worker_recovery" || root.data().testOnly !== true) throw Object.assign(new Error("fixture_not_authorized"), {statusCode: 403});
    result = await (options.run || runWorker)({db: fixtureDb(rawDb, input.fixtureId), worker, now: Date.now(), limit: 20});
   } else if (mode === "dry-run") {
    const collections = worker === "markStaleRiderPresenceOffline" ? ["riderPresence"] : ["deliveryRequests", "deliveryOperationalState", "deliveryMaintenanceJobs"];
    result = {};
    for (const name of collections) result[name] = (await rawDb.collection(name).limit(20).get()).size;
    result.dryRun = true;
   } else if (mode === "tick") {
    if (process.env.DELIVERY_WORKERS_READY !== "true" && !options.ready) throw Object.assign(new Error("worker_not_enabled"), {statusCode: 503});
    result = await processTick({db: rawDb, worker, tick: parseTick(worker, input), run: options.run || runWorker});
   } else throw Object.assign(new Error("not_found"), {statusCode: 404});
   console.info("delivery_maintenance_completed", {worker, mode, result}); send(200, {ok: true, worker, result});
  } catch (error) {
console.warn("delivery_maintenance_failed", {worker, code: error.code || error.message}); send(error.statusCode || 503, {error: error.statusCode ? error.message : "worker_failed"});
}
 }); return true;
}
module.exports = {handleMaintenance, parseTick, processTick, INTERVALS};
