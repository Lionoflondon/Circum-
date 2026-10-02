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
