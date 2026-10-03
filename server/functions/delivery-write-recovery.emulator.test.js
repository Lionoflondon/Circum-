/* eslint-disable max-len, require-jsdoc */
"use strict";
const test = require("node:test"); const assert = require("node:assert/strict");
const {initializeApp, deleteApp} = require("firebase-admin/app"); const {getFirestore} = require("firebase-admin/firestore");
const {projectTimeline, projectPresence} = require("./delivery-write-recovery");
async function fixture(name, run) {
 assert.ok(process.env.FIRESTORE_EMULATOR_HOST); const app = initializeApp({projectId: `demo-delivery-write-${name}`}, name);
 try {
await run(getFirestore(app));
} finally {
await deleteApp(app);
}
}
test("delayed terminal events preserve the new assignment live location and write historical timeline once", () => fixture("timeline", async (db) => {
 await db.doc("deliveryRequests/job").set({status: "accepted", riderId: "new"}); await db.doc("deliveryLiveLocations/job").set({riderId: "new", trackingStatus: "active"});
 const event = {deliveryId: "job", eventId: "old-terminal", time: "2026-10-01T10:00:00Z", before: {status: "accepted", riderId: "old"}, after: {status: "completed", riderId: "old"}};
 await Promise.all(Array.from({length: 4}, () => projectTimeline({db, event})));
 assert.ok((await db.doc("deliveryLiveLocations/job").get()).exists); const rows = await db.collection("deliveryRequests/job/timeline").get(); assert.equal(rows.size, 1); assert.equal(rows.docs[0].data().timestamp.toDate().toISOString(), event.time.replace("Z", ".000Z"));
 await db.doc("deliveryRequests/job").update({status: "completed"}); await projectTimeline({db, event: {...event, eventId: "current-terminal"}}); assert.equal((await db.doc("deliveryLiveLocations/job").get()).exists, false);
}));
test("guest upload authorization uses its isolated token records and never signs another Gift path", () => fixture("guest-upload", async (db) => {
 const {createStoryVideoUpload, storyRuntimeDb} = require("./gift-story-automation");
 const {Timestamp} = require("firebase-admin/firestore"); const {createHash} = require("node:crypto");
 const id = "__codex_video_guest_upload"; const token = `${id}.` + "x".repeat(32);
 await db.doc(`giftStoryRuntimeFixtures/${id}`).set({purpose: "gift_video_certification", testOnly: true, suppressExternalSideEffects: true});
 const scoped = await storyRuntimeDb(db, {token});
 await scoped.collection("giftRequests").doc(id).set({status: "completed", senderId: "existing-test-sender"});
 const hash = createHash("sha256").update(token).digest("hex");
 await scoped.collection("giftStoryAccessTokens").doc(hash).set({status: "active", giftRequestId: id, role: "recipient", expiresAt: Timestamp.fromMillis(Date.now() + 60000)});
 const paths = []; const bucket = {file: (path) => ({getSignedUrl: async (options) => {
paths.push(path); assert.equal(options.action, "write"); assert.equal(options.contentType, "video/webm"); return ["https://test-only.invalid/scoped-upload"];
}})};
 const result = await createStoryVideoUpload({db: scoped, bucket, data: {giftRequestId: id, token}, context: {}});
 assert.ok(result.storagePath.startsWith(`runtime-fixtures/gift-video/${id}/exports/sound/`)); assert.equal(paths.length, 1);
 await assert.rejects(createStoryVideoUpload({db: scoped, bucket, data: {giftRequestId: id, token: token + "invalid"}, context: {}}), {code: "permission-denied"}); assert.equal(paths.length, 1);
 await scoped.collection("giftStoryAccessTokens").doc(hash).update({expiresAt: Timestamp.fromMillis(Date.now() - 1)});
 await assert.rejects(createStoryVideoUpload({db: scoped, bucket, data: {giftRequestId: id, token}, context: {}}), {code: "permission-denied"}); assert.equal(paths.length, 1);
 assert.equal((await db.collection("giftRequests").get()).size, 0);
}));
test("delivery presence reads fresh assignment and preserves offline intent and newer lock aliases", () => fixture("presence", async (db) => {
 await db.doc("deliveryRequests/job").set({status: "accepted", riderId: "new"});
 await db.doc("riderPresence/old").set({isOnline: false, onlineIntent: false, busy: true, activeDeliveryId: "other", currentDeliveryId: "other"});
 await db.doc("riderPresence/new").set({isOnline: false, onlineIntent: false, busy: false});
 const event = {deliveryId: "job", eventId: "stale-completed", before: {status: "accepted", riderId: "old"}, after: {status: "completed", riderId: "old"}};
 await Promise.all(Array.from({length: 4}, () => projectPresence({db, event})));
 const old = (await db.doc("riderPresence/old").get()).data(); const current = (await db.doc("riderPresence/new").get()).data();
 assert.equal(old.activeDeliveryId, "other"); assert.equal(old.busy, true); assert.equal(current.activeDeliveryId, "job"); assert.equal(current.busy, true); assert.equal(current.isOnline, false); assert.equal(current.onlineIntent, false); assert.equal((await db.collection("eventHandlerClaims").get()).size, 1);
 await db.doc("deliveryRequests/job").update({status: "completed"}); await projectPresence({db, event: {...event, eventId: "fresh-completed"}}); const finished = (await db.doc("riderPresence/new").get()).data(); assert.equal(finished.busy, false); assert.equal(finished.isOnline, false); assert.equal(finished.activeDeliveryId, null);
}));
test("tracking retries preserve a single immutable event without changing delivery state", () => fixture("tracking", async (db) => {
 await db.doc("deliveryRequests/job").set({status: "in_transit", riderId: "rider"}); const event = {deliveryId: "job", eventId: "tracking-start", before: null, after: {riderId: "rider", trackingStatus: "active"}};
 await Promise.all(Array.from({length: 3}, () => projectTimeline({db, event, live: true}))); assert.equal((await db.collection("deliveryRequests/job/timeline").get()).size, 1); assert.equal((await db.doc("deliveryRequests/job").get()).data().status, "in_transit");
}));
test("Gift Story TEST scope requires server-owned markers and cannot redirect ordinary gifts", () => fixture("story-scope", async (db) => {
 const {storyRuntimeDb} = require("./gift-story-automation"); const id = "__codex_video_scope_test"; const root = db.doc(`giftStoryRuntimeFixtures/${id}`);
 await assert.rejects(storyRuntimeDb(db, {giftRequestId: id}), {code: "not-found"});
 await root.set({purpose: "gift_video_certification", testOnly: true, suppressExternalSideEffects: false}); await assert.rejects(storyRuntimeDb(db, {giftRequestId: id}), {code: "not-found"});
 await root.update({suppressExternalSideEffects: true}); const scoped = await storyRuntimeDb(db, {token: `${id}.` + "x".repeat(32)}); assert.equal(scoped.fixtureMode, true);
 await scoped.collection("giftRequests").doc(id).set({status: "test"}); assert.equal((await db.doc(`giftRequests/${id}`).get()).exists, false);
 assert.equal(await storyRuntimeDb(db, {giftRequestId: "ordinary", token: "opaque"}), db);
}));

test("Health movement retries read fresh payment and hold unpaid pickups without financial writes", () => fixture("health-unpaid", async (db) => {
 const {projectHealth} = require("./special-movement-recovery");
 await db.doc("prescriptionPickups/pickup").set({status: "requested", senderId: "sender", readyForCollection: true});
 const event = {deliveryId: "pickup", eventId: "stale-paid", after: {paymentStatus: "paid"}};
 await Promise.all(Array.from({length: 3}, () => projectHealth({db, event})));
 let delivery = (await db.doc("deliveryRequests/health_pickup").get()).data(); assert.equal(delivery.matchingStatus, "held"); assert.equal(delivery.healthDispatchReady, false);
 await db.doc("healthPlusPayments/pickup").set({status: "paid", amount: 12});
 await projectHealth({db, event: {...event, eventId: "fresh-paid"}}); delivery = (await db.doc("deliveryRequests/health_pickup").get()).data(); assert.equal(delivery.matchingStatus, "available"); assert.equal(delivery.paymentStatus, "paid");
 assert.equal((await db.collection("walletTransactions").get()).size, 0); assert.equal((await db.collection("riderEarningTransactions").get()).size, 0);
}));
test("Health projection cannot overwrite accepted custody or terminal state from a delayed source event", () => fixture("health-custody", async (db) => {
 const {projectHealth} = require("./special-movement-recovery");
 await db.doc("prescriptionPickups/pickup").set({status: "requested", riderId: "old", paymentStatus: "paid"});
 await db.doc("deliveryRequests/health_pickup").set({status: "in_transit", riderId: "new", paymentStatus: "paid", sourceModule: "health_plus", healthPlusPickupId: "pickup"});
 await projectHealth({db, event: {deliveryId: "pickup", eventId: "old"}});
 let d = (await db.doc("deliveryRequests/health_pickup").get()).data(); assert.equal(d.status, "in_transit"); assert.equal(d.riderId, "new");
 await db.doc("deliveryRequests/health_pickup").update({status: "delivered"}); await projectHealth({db, event: {deliveryId: "pickup", eventId: "later"}}); d = (await db.doc("deliveryRequests/health_pickup").get()).data(); assert.equal(d.status, "delivered");
}));
test("terminal movement retries use current delivery and preserve a newer linked assignment", () => fixture("terminal-fresh", async (db) => {
 const {projectTerminal} = require("./special-movement-recovery");
 await db.doc("deliveryRequests/job").set({status: "accepted", riderId: "new", sourceModule: "gifts", giftRequestId: "gift"}); await db.doc("giftRequests/gift").set({status: "preparing", riderId: "new", deliveryId: "job"});
 const event = {deliveryId: "job", eventId: "old-completed", after: {status: "delivered", riderId: "old"}};
 await projectTerminal({db, event}); assert.equal((await db.doc("giftRequests/gift").get()).data().status, "preparing");
 await db.doc("deliveryRequests/job").update({status: "delivered", riderId: "old"}); await projectTerminal({db, event: {...event, eventId: "conflict"}}); assert.equal((await db.doc("giftRequests/gift").get()).data().riderId, "new");
 await db.doc("deliveryRequests/job").update({riderId: "new"}); await Promise.all(Array.from({length: 3}, () => projectTerminal({db, event: {...event, eventId: "current"}}))); assert.equal((await db.doc("giftRequests/gift").get()).data().status, "delivered"); assert.equal((await db.collection("eventHandlerClaims").get()).size, 3);
}));
test("terminal projections preserve cancellation and never recreate deleted linked records", () => fixture("terminal-cancel", async (db) => {
 const {projectTerminal} = require("./special-movement-recovery");
 await db.doc("deliveryRequests/job").set({status: "delivered", sourceModule: "health_plus", healthPlusPickupId: "pickup"}); await db.doc("prescriptionPickups/pickup").set({status: "cancelled"});
 await projectTerminal({db, event: {deliveryId: "job", eventId: "conflict"}}); assert.equal((await db.doc("prescriptionPickups/pickup").get()).data().status, "cancelled");
 await db.doc("prescriptionPickups/pickup").delete(); await projectTerminal({db, event: {deliveryId: "job", eventId: "deleted"}}); assert.equal((await db.doc("prescriptionPickups/pickup").get()).exists, false);
}));

test("Health recovery preserves an existing alternate source delivery binding", () => fixture("health-binding", async (db) => {
 const {projectHealth} = require("./special-movement-recovery");
 await db.doc("prescriptionPickups/pickup").set({status: "requested", deliveryId: "newer-canonical", sourceModule: "health_plus"});
 const result = await projectHealth({db, event: {deliveryId: "pickup", eventId: "old-binding"}});
 assert.equal(result.reason, "source_identity_conflict"); assert.equal((await db.doc("deliveryRequests/health_pickup").get()).exists, false); assert.equal((await db.doc("prescriptionPickups/pickup").get()).data().deliveryId, "newer-canonical");
}));

test("completion redelivery stays retryable during an active lease and recovers after a crashed attempt", () => fixture("completion-lease", async (db) => {
 const {runSubscriber} = require("./delivery-completed-event")._private;
 const event = {eventId: "delivery_completed_test"}; const ref = db.doc("platformEventSubscribers/delivery_completed_test_sender"); let calls = 0;
 await ref.set({status: "processing", startedAt: Date.now()});
 await assert.rejects(runSubscriber(db, event, "sender", async () => {
 calls++;
}), {code: "aborted"});
 assert.equal(calls, 0); assert.equal((await ref.get()).data().status, "processing");
 await ref.update({startedAt: Date.now() - 11 * 60 * 1000});
 const recovered = await runSubscriber(db, event, "sender", async () => {
 calls++;
});
 assert.equal(recovered.skipped, false); assert.equal(calls, 1); assert.equal((await ref.get()).data().status, "done");
 const duplicate = await runSubscriber(db, event, "sender", async () => {
 calls++;
});
 assert.equal(duplicate.skipped, true); assert.equal(calls, 1);
}));
test("partial completion referral rewards remain retryable rather than being marked complete", () => fixture("completion-review", async (db) => {
 const {runSubscriber} = require("./delivery-completed-event")._private;
 const event = {eventId: "delivery_completed_review"}; const ref = db.doc("platformEventSubscribers/delivery_completed_review_referrals"); let attempts = 0;
 await assert.rejects(runSubscriber(db, event, "referrals", async () => {
 attempts++; return {sender: {status: "rothAwarded"}, rider: {status: "review"}};
}), {code: "aborted"});
 assert.equal((await ref.get()).data().status, "failed");
 await runSubscriber(db, event, "referrals", async () => {
 attempts++; return {sender: {status: "rothAwarded"}, rider: {status: "rothAwarded"}};
});
 assert.equal(attempts, 2); assert.equal((await ref.get()).data().status, "done");
}));
