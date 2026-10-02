/* eslint-disable max-len */
"use strict";
const {test} = require("node:test");
const assert = require("node:assert/strict");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore, Timestamp} = require("firebase-admin/firestore");
const {activateOne, escalation, watchdogOne, stalePresence, runWorker} = require("./delivery-maintenance-core");
const {processTick} = require("./delivery-maintenance-http");
const {processNotificationRetriesCore} = require("./notification-retry-core");
async function withDb(name, run) {
 assert.ok(process.env.FIRESTORE_EMULATOR_HOST);
 const app = initializeApp({projectId: `demo-maintenance-${name}`}, name);
 try {
return await run(getFirestore(app));
} finally {
await deleteApp(app);
}
}
test("concurrent activation commits one state transition and a durable dispatch job", () => withDb("activation", async (db) => {
 const now = Date.now(); const ref = db.doc("deliveryRequests/scheduled");
 await ref.set({status: "scheduled", productType: "standard", fulfilmentMode: "scheduled", scheduledAt: Timestamp.fromMillis(now - 1000), senderId: "test", requestId: "scheduled"});
 const results = await Promise.all(Array.from({length: 8}, () => activateOne(db, "scheduled", now)));
 assert.equal(results.filter((x) => x.activated).length, 1);
 assert.equal((await db.collection("deliveryMaintenanceJobs").get()).size, 1);
 assert.equal((await ref.get()).data().status, "requested");
 // Simulate a crash after activation, then acceptance before the dispatch retry.
 await ref.set({status: "accepted", riderId: "rider", dispatchStatus: "accepted"}, {merge: true});
 await runWorker({db, worker: "activateDueScheduledDeliveries", now});
 assert.equal((await ref.get()).data().dispatchStatus, "accepted");
 assert.equal((await db.collection("deliveryMaintenanceJobs").get()).docs[0].data().state, "completed");
 assert.equal((await db.collection("notifications").get()).size, 0);
}));
test("reserved Rider readiness and concurrent active work are rechecked before activation", () => withDb("reserved", async (db) => {
 const now = Date.now(); await db.doc("deliveryRequests/job").set({status: "scheduled", productType: "gift", scheduledAt: Timestamp.fromMillis(now - 1000), assignedRiderId: "rider"});
 await db.doc("riderProfiles/rider").set({riderStatus: "approved", vehicleApproved: true});
 await db.doc("riderPresence/rider").set({busy: true, activeDeliveryId: "another"});
 assert.equal((await activateOne(db, "job", now)).blocked, true);
 assert.equal((await db.doc("deliveryRequests/job").get()).data().status, "scheduled");
}));
test("escalation notifications and stage checkpoint are one retry-safe transaction", () => withDb("escalation", async (db) => {
 const now = Date.now(); await db.doc("deliveryRequests/open").set({status: "requested", createdAt: Timestamp.fromMillis(now - 10 * 60000)});
 await Promise.all(Array.from({length: 5}, () => escalation({db, now, limit: 20})));
 assert.equal((await db.collection("notifications").get()).size, 1);
 assert.equal((await db.doc("deliveryRequests/open").get()).data().notificationEscalationStage, 5);
 await escalation({db, now, limit: 20}); assert.equal((await db.collection("notifications").get()).size, 1);
}));
test("concurrent watchdog execution produces one incident, timeline entry and alert", () => withDb("watchdog", async (db) => {
 const now = Date.now(); await db.doc("deliveryRequests/job").set({status: "accepted", riderId: "rider"});
 await db.doc("deliveryOperationalState/job").set({status: "accepted", incidentType: "accepted_no_movement", assignedRiderId: "rider", active: true, stateEnteredAt: Timestamp.fromMillis(now - 20 * 60000), nextCheckAt: Timestamp.fromMillis(now - 60000)});
 await Promise.all(Array.from({length: 6}, () => watchdogOne(db, "job", now)));
 assert.equal((await db.collection("operationalIncidents").get()).size, 1);
 assert.equal((await db.collection("notifications").get()).size, 1);
 assert.equal((await db.doc("deliveryRequests/job").collection("timeline").get()).size, 1);
 await db.doc("deliveryRequests/job").set({status: "completed"}, {merge: true}); await watchdogOne(db, "job", now + 1000);
 assert.equal((await db.collection("operationalIncidents").get()).docs[0].data().status, "RESOLVED");
 assert.equal((await db.doc("deliveryOperationalState/job").get()).data().active, false);
}));
test("stale projections do not create incidents for progressed deliveries", () => withDb("progressed", async (db) => {
 const now = Date.now(); await db.doc("deliveryRequests/job").set({status: "completed"});
 await db.doc("deliveryOperationalState/job").set({status: "accepted", incidentType: "accepted_no_movement", active: true, nextCheckAt: Timestamp.fromMillis(now - 60000)});
 await watchdogOne(db, "job", now); assert.equal((await db.collection("operationalIncidents").get()).size, 0);
}));
test("a heartbeat arriving after the stale query cannot be overwritten", () => withDb("heartbeat", async (db) => {
 const now = Date.now(); const ref = db.doc("riderPresence/rider"); await ref.set({isOnline: true, lastHeartbeatAt: now - 10 * 60000, dispatchEligible: true});
 const raceDb = {collection: db.collection.bind(db), runTransaction: async (run) => {
await ref.set({lastHeartbeatAt: now}, {merge: true}); return db.runTransaction(run);
}};
 assert.equal((await stalePresence({db: raceDb, now, limit: 20})).markedStale, 0);
 assert.equal((await ref.get()).data().dispatchEligible, true);
}));
test("receipt replay, coalescing, acknowledgement budgets and crashes are bounded", () => withDb("receipts", async (db) => {
 const worker = "activateDueScheduledDeliveries"; const now = Date.now(); const ref = db.doc(`deliveryWorkerControl/${worker}`); await ref.set({enabled: true, maxAcknowledgements: 2, batchLimit: 1});
 let runs = 0; const run = async () => {
runs++; return {safe: true};
}; const tick = (id) => ({messageId: id, publishTime: new Date(now - 86400000).toISOString(), ageSeconds: 86400});
 await processTick({db, worker, now, tick: tick("1"), run}); await processTick({db, worker, now, tick: tick("1"), run}); await processTick({db, worker, now, tick: tick("2"), run});
 assert.equal(runs, 1); assert.equal((await ref.get()).data().acknowledged, 2);
 await assert.rejects(processTick({db, worker, now, tick: tick("3"), run}), /bounded_cutover_paused/);
 await ref.set({maxAcknowledgements: 3}, {merge: true});
 await assert.rejects(processTick({db, worker, now: now + 120000, tick: tick("3"), run: async () => {
throw new Error("crash");
}}), /crash/);
 assert.equal((await ref.get()).data().acknowledged, 2);
 await processTick({db, worker, now: now + 120000, tick: tick("3"), run}); assert.equal((await ref.get()).data().acknowledged, 3);
}));
test("durable admin alert uses active admins and uncertain sends are not replayed", () => withDb("admin-push", async (db) => {
 const now = Date.now(); await db.doc("deliveryRequests/open").set({status: "requested", createdAt: Timestamp.fromMillis(now - 10 * 60000)});
 await escalation({db, now, limit: 20}); await db.doc("adminUsers/active").set({status: "active", fcmToken: "active-token"}); await db.doc("adminUsers/disabled").set({status: "disabled", fcmToken: "disabled-token"});
 let sent = 0; const sendPush = async (message) => {
sent++; assert.deepEqual(message.tokens, ["active-token"]); throw Object.assign(new Error("unknown"), {code: "push_outcome_unknown"});
};
 await processNotificationRetriesCore({db, now, sendPush}); await processNotificationRetriesCore({db, now: now + 60000, sendPush}); assert.equal(sent, 1);
 assert.equal((await db.collection("notifications").get()).docs[0].data().pushDeliveryStatus, "manual_review");
}));
test("acceptance racing the final dispatch commit preserves the accepted authority", () => withDb("dispatch-race", async (db) => {
 const {dispatchDeliveryRequest} = require("./send-package");
 const {GeoPoint} = require("firebase-admin/firestore");
 const ref = db.doc("deliveryRequests/job"); await ref.set({requestId: "job", senderId: "sender", status: "requested", dispatchStatus: "requested", packageDescription: "A small paperback book", weight: "0.5 kg", distanceMiles: 1, pickupPosition: {geopoint: new GeoPoint(51, 0)}});
 const raced = {collection: db.collection.bind(db), runTransaction: async (run) => {
await ref.set({status: "accepted", riderId: "rider", dispatchStatus: "accepted"}, {merge: true}); return db.runTransaction(run);
}};
 await dispatchDeliveryRequest({db: raced, requestId: "job", uid: "sender", durableOnly: true}); assert.equal((await ref.get()).data().dispatchStatus, "accepted");
}));
test("recovered dispatch persists one eligible Rider offer and survives retry without sending providers", () => withDb("dispatch-offer", async (db) => {
 const now = Date.now(); const {GeoPoint} = require("firebase-admin/firestore"); const {dispatchDeliveryRequest} = require("./send-package");
 await db.doc("deliveryRequests/job").set({requestId: "job", senderId: "sender", status: "requested", dispatchStatus: "requested", packageDescription: "A small paperback book", weight: "0.5 kg", distanceMiles: 1, pickupPosition: {geopoint: new GeoPoint(51, 0.1)}});
 const profile = {status: "online", approvalStatus: "approved", riderStatus: "approved", vehicleApproved: true, vehicleType: "van", availabilityStatus: "available", position: {geopoint: new GeoPoint(51.001, 0.1)}};
 await db.doc("riders/rider").set(profile); await db.doc("riderProfiles/rider").set(profile);
 await db.doc("riderPresence/rider").set({isOnline: true, availabilityStatus: "available", busy: false, dispatchEligible: true, lastHeartbeatAt: now, currentLocation: {latitude: 51.001, longitude: 0.1, accuracyMeters: 10, updatedAt: now}});
 await dispatchDeliveryRequest({db, requestId: "job", uid: "sender", durableOnly: true}); await dispatchDeliveryRequest({db, requestId: "job", uid: "sender", durableOnly: true});
 const notes = await db.collection("notifications").get(); assert.equal(notes.size, 1); assert.equal(notes.docs[0].data().recipientId, "rider"); assert.equal(notes.docs[0].data().failureReason, "retry_worker_exited_before_send"); assert.equal((await db.doc("deliveryRequests/job").get()).data().dispatchStatus, "broadcasted");
}));
test("already-stale Riders cannot starve later presence pages", () => withDb("presence-pages", async (db) => {
 const now = Date.now(); await db.doc("riderPresence/a").set({isOnline: true, lastHeartbeatAt: now - 600000, presenceFreshness: "stale"}); await db.doc("riderPresence/b").set({isOnline: true, lastHeartbeatAt: now - 600000});
 assert.equal((await stalePresence({db, now, limit: 1})).markedStale, 0); assert.equal((await stalePresence({db, now, limit: 1})).markedStale, 1); assert.equal((await db.doc("riderPresence/b").get()).data().presenceFreshness, "stale");
}));
