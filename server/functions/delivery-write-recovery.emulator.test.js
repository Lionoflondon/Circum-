/* eslint-disable max-len, require-jsdoc */
"use strict";
const test = require("node:test"); const assert = require("node:assert/strict");
const {initializeApp, deleteApp} = require("firebase-admin/app"); const {getFirestore} = require("firebase-admin/firestore");
const {projectTimeline, projectPresence} = require("./delivery-write-recovery");
const {projectOperational} = require("./health-operational-recovery");
test("concurrent Health operational delivery events debit one allowance and preserve read/provider state", () => fixture("health-usage", async (db) => {
 const pickup = {status: "delivered", scheduleId: "schedule", senderId: "fixture-only", email: "fixture@example.invalid", assignedDriverId: "fixture-rider"};
 await db.doc("prescriptionPickups/job").set(pickup); await db.doc("recurringPickupSchedules/schedule").set({planType: "basic", usedDeliveriesThisCycle: 0, usedPickupsThisCycle: 0});
 const event = {deliveryId: "job", eventId: "health-first", before: {status: "collected"}, after: pickup, time: new Date().toISOString()};
 await Promise.all(Array.from({length: 4}, (_, i) => projectOperational({db, event: {...event, eventId: `concurrent-${i}`}})));
 const plan = (await db.doc("recurringPickupSchedules/schedule").get()).data(); assert.equal(plan.usedDeliveriesThisCycle, 1); assert.equal(plan.usedPickupsThisCycle, 1); assert.equal(plan.remainingDeliveriesThisCycle, 1); assert.equal(plan.remainingPickupsThisCycle, 1);
 const noticeRef = db.doc("healthPlusNotifications/health_job_delivered"); const created = (await noticeRef.get()).data().createdAt; await noticeRef.update({read: true}); await db.doc("emailQueue/health_job_delivered").update({status: "sent", attempts: 1});
 await projectOperational({db, event}); const replay = await projectOperational({db, event}); assert.equal(replay.outcome, "DUPLICATE");
 const notice = (await noticeRef.get()).data(); assert.equal(notice.read, true); assert.ok(notice.createdAt.isEqual(created)); assert.equal((await db.doc("emailQueue/health_job_delivered").get()).data().status, "sent"); assert.equal((await db.doc("recurringPickupSchedules/schedule").get()).data().usedDeliveriesThisCycle, 1);
 assert.equal((await db.collection("healthPlusUsageEvents").get()).size, 1); assert.equal((await db.collection("healthPlusCustodyArchive").get()).size, 1); assert.equal((await db.collection("walletTransactions").get()).size, 0);
}));
test("legacy Health usage ambiguity is held for review rather than incrementing again", () => fixture("health-legacy-usage", async (db) => {
 const pickup = {status: "delivered", scheduleId: "schedule", senderId: "fixture-only"}; await db.doc("prescriptionPickups/job").set(pickup); await db.doc("recurringPickupSchedules/schedule").set({planType: "basic", usedDeliveriesThisCycle: 1}); await db.doc("healthPlusCustodyArchive/job_delivered_delivered").set({legacy: true});
 const event = {deliveryId: "job", eventId: "legacy", after: pickup, time: new Date().toISOString()}; const first = await projectOperational({db, event}); assert.equal(first.outcome, "MANUAL_REVIEW"); await projectOperational({db, event: {...event, eventId: "other-transport"}});
 assert.equal((await db.doc("recurringPickupSchedules/schedule").get()).data().usedDeliveriesThisCycle, 1); assert.equal((await db.collection("healthPlusOperationalErrors").get()).size, 1); assert.equal((await db.collection("healthPlusUsageEvents").get()).size, 0);
}));
test("Health usage cannot charge the current monthly allowance for a prior-cycle completion", () => fixture("health-old-cycle", async (db) => {
 const old = new Date(); old.setMonth(old.getMonth() - 2);
 const pickup = {status: "delivered", scheduleId: "schedule", deliveredAt: old}; await db.doc("prescriptionPickups/job").set(pickup); await db.doc("recurringPickupSchedules/schedule").set({planType: "basic", usedDeliveriesThisCycle: 0});
 const result = await projectOperational({db, event: {deliveryId: "job", eventId: "old-cycle", after: {status: "delivered"}, time: old.toISOString()}}); assert.equal(result.outcome, "MANUAL_REVIEW"); assert.equal((await db.doc("recurringPickupSchedules/schedule").get()).data().usedDeliveriesThisCycle, 0); assert.equal((await db.doc("healthPlusOperationalErrors/delivery_usage_job").get()).data().reason, "prior_cycle_delivery_event");
}));
test("Health stale payloads and failed accounting transactions leave no partial notification or debit", () => fixture("health-atomic", async (db) => {
 const pickup = {status: "delivered", scheduleId: "schedule", assignedDriverId: "new"}; await db.doc("prescriptionPickups/job").set(pickup); await db.doc("recurringPickupSchedules/schedule").set({planType: "basic", usedDeliveriesThisCycle: -1});
 const stale = await projectOperational({db, event: {deliveryId: "job", eventId: "stale", after: {status: "assigned", assignedDriverId: "old"}}}); assert.equal(stale.outcome, "IGNORED");
 await assert.rejects(projectOperational({db, event: {deliveryId: "job", eventId: "atomic-failure", after: pickup, time: new Date().toISOString()}}), /invalid_health_usage_counter/);
 assert.equal((await db.collection("healthPlusCustodyArchive").get()).size, 0); assert.equal((await db.collection("healthPlusNotifications").get()).size, 0); assert.equal((await db.collection("healthPlusUsageEvents").get()).size, 0); assert.equal((await db.doc("eventHandlerClaims/health_operational_" + require("node:crypto").createHash("sha256").update("atomic-failure").digest("hex")).get()).exists, false);
 await db.doc("recurringPickupSchedules/schedule").update({usedDeliveriesThisCycle: 0}); await projectOperational({db, event: {deliveryId: "job", eventId: "atomic-failure", after: pickup, time: new Date().toISOString()}}); assert.equal((await db.doc("recurringPickupSchedules/schedule").get()).data().usedDeliveriesThisCycle, 1);
}));
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

test("founding recognition recovers missing helpers but preserves current approval and unique numbers on replay", () => fixture("recognition", async (db) => {
 const {awardRecognition} = require("./legends")._private;
 const ref = db.doc("riderProfiles/test_rider"); await ref.set({approvalStatus: "pending"});
 const run = () => awardRecognition({db, type: "foundingRider", subjectRef: ref, subjectId: "test_rider", subjectCollection: "riderProfiles", source: "rider_application_accepted"});
 assert.equal((await run()).reason, "current_approval_required"); assert.equal((await db.collection("recognitionCounters").get()).size, 0);
 await ref.update({approvalStatus: "approved"}); const results = await Promise.all([run(), run(), run()]);
 assert.equal(results.filter((r) => r.awarded).length, 1); assert.equal((await ref.get()).data().foundingRiderNumber, 1);
 assert.equal((await db.collection("recognitionAwards").get()).size, 1); assert.equal((await db.collection("recognitionNumbers").get()).size, 1);
 assert.equal((await db.doc("recognitionCounters/foundingRider").get()).data().totalAwarded, 1);
 assert.equal((await db.collection("walletTransactions").get()).size, 0);
}));

test("completion Legend helper preserves the canonical counter and awards a paid completion only once", () => fixture("legend-helper", async (db) => {
 const {handleDeliveryCompleted} = require("./legends");
 await db.doc("users/test_sender").set({isLegend: false}); await db.doc("deliveryRequests/job").set({status: "completed", paymentStatus: "paid", senderId: "test_sender"});
 await Promise.all([handleDeliveryCompleted({db, deliveryId: "job"}), handleDeliveryCompleted({db, deliveryId: "job"})]);
 assert.equal((await db.doc("platformStats/legends").get()).data().totalAwarded, 1);
 assert.equal((await db.doc("platformStats/legends").get()).data().limit, 1500);
 assert.equal((await db.doc("users/test_sender").get()).data().legendNumber, 1);
 assert.equal((await db.doc("deliveryRequests/job").get()).data().legendAwarded, true);
 assert.equal((await db.collection("recognitionCounters").get()).size, 0);
 await db.doc("deliveryRequests/job").update({refundStatus: "partially_refunded"}); await handleDeliveryCompleted({db, deliveryId: "job"});
 assert.equal((await db.doc("platformStats/legends").get()).data().totalAwarded, 1);
}));
test("completion bus records notification provenance through the existing owner without customer notification writes", () => fixture("notification-owner", async (db) => {
 const {_private} = require("./delivery-completed-event");
 const result = await _private.subscribers.notifications(db, {eventId: "test_completed", deliveryId: "test_delivery", senderId: "test_sender", riderId: null, recipientId: null});
 assert.equal(result.reason, "platform_event_not_canonical_notification_owner");
 assert.equal((await db.doc("platformNotifications/test_completed").get()).data().canonicalNotificationOwner, "circum-sender-notification-events");
 assert.equal((await db.collection("notifications").get()).size, 0);
}));

test("manual and automatic Legend awards share the existing counter instead of assigning duplicate numbers", () => fixture("legend-counter", async (db) => {
 const {handleDeliveryCompleted, _private} = require("./legends");
 await db.doc("users/automatic").set({}); await db.doc("users/manual").set({});
 await db.doc("deliveryRequests/job").set({status: "completed", paymentStatus: "paid", senderId: "automatic"});
 await handleDeliveryCompleted({db, deliveryId: "job"});
 await _private.awardRecognition({db, type: "legend", subjectRef: db.doc("users/manual"), subjectId: "manual", subjectCollection: "users", source: "admin"});
 assert.equal((await db.doc("users/automatic").get()).data().legendNumber, 1);
 assert.equal((await db.doc("users/manual").get()).data().legendNumber, 2);
 assert.equal((await db.doc("platformStats/legends").get()).data().totalAwarded, 2);
 assert.equal((await db.doc("recognitionCounters/legend").get()).exists, false);
}));

test("completion linked projections preserve fresh reassignment, cancellations and missing records", () => fixture("completion-links", async (db) => {
 const {projectLinkedCompletion} = require("./delivery-completed-event")._private;
 const event = {eventId: "delivery_completed_job", deliveryId: "job", riderId: "old", completedAt: new Date(), healthOrderId: "pickup"};
 await db.doc("deliveryRequests/job").set({status: "accepted", riderId: "new", healthOrderId: "pickup"});
 await db.doc("prescriptionPickups/pickup").set({status: "requested", deliveryId: "job", riderId: "new"});
 await projectLinkedCompletion(db, event, "prescriptionPickups", "pickup"); assert.equal((await db.doc("prescriptionPickups/pickup").get()).data().status, "requested");
 await db.doc("deliveryRequests/job").update({status: "delivered"}); await projectLinkedCompletion(db, event, "prescriptionPickups", "pickup"); assert.equal((await db.doc("prescriptionPickups/pickup").get()).data().status, "requested");
 await db.doc("prescriptionPickups/pickup").update({status: "cancelled"}); await projectLinkedCompletion(db, {...event, riderId: "new"}, "prescriptionPickups", "pickup"); assert.equal((await db.doc("prescriptionPickups/pickup").get()).data().status, "cancelled");
 await db.doc("prescriptionPickups/pickup").delete(); await projectLinkedCompletion(db, {...event, riderId: "new"}, "prescriptionPickups", "pickup"); assert.equal((await db.doc("prescriptionPickups/pickup").get()).exists, false);
 await db.doc("prescriptionPickups/pickup").set({status: "requested", deliveryId: "job", riderId: "new"}); await projectLinkedCompletion(db, {...event, riderId: "new"}, "prescriptionPickups", "pickup"); assert.equal((await db.doc("prescriptionPickups/pickup").get()).data().status, "delivered"); assert.equal((await db.collection("healthPlusNotifications").get()).size, 1);
 await db.doc("prescriptionPickups/pickup").update({status: "completed"}); await projectLinkedCompletion(db, {...event, riderId: "new"}, "prescriptionPickups", "pickup"); assert.equal((await db.doc("prescriptionPickups/pickup").get()).data().status, "completed");
}));
test("a replaced completion lease cannot be marked done by its stale worker", () => fixture("completion-fence", async (db) => {
 const {claimSubscriber, settleSubscriber} = require("./delivery-completed-event")._private;
 const old = await claimSubscriber(db, "delivery_completed_job", "sender"); await old.ref.update({startedAt: 0}); const fresh = await claimSubscriber(db, "delivery_completed_job", "sender");
 assert.equal(fresh.claimed, true); await assert.rejects(settleSubscriber(db, old, {status: "done"}), /lease_lost/); assert.equal((await fresh.ref.get()).data().status, "processing"); await settleSubscriber(db, fresh, {status: "done"});
}));
test("partial referral completion retries the existing deterministic Roth movements once", () => fixture("completion-referral-ledger", async (db) => {
 const referrals = require("./referrals"); const ledger = require("./roth-ledger"); const original = ledger.recordRothMovement; let fail = true;
 await db.doc("deliveryRequests/job").set({status: "delivered", paymentStatus: "paid", senderId: "fixture_referred"});
 await db.doc("referrals/fixture_referred").set({status: "signed_up", referrerUserId: "fixture_inviter", rewardAmount: 5});
 ledger.recordRothMovement = async (args) => {
  if (args.transactionId.endsWith("_referred") && fail) {
fail = false; throw new Error("test_crash_after_inviter_movement");
} return original(args);
 };
 try {
  const args = {db, deliveryId: "job", delivery: {senderId: "fixture_referred"}};
  assert.equal((await referrals.handleDeliveryCompletedReferral(args)).sender.status, "review");
  assert.equal((await db.collection("walletTransactions").get()).size, 1);
  assert.equal((await referrals.handleDeliveryCompletedReferral(args)).sender.status, "ROTH_AWARDED");
  await referrals.handleDeliveryCompletedReferral(args);
  assert.equal((await db.collection("walletTransactions").get()).size, 2);
  assert.equal((await db.doc("referrals/fixture_referred").get()).data().needsReview, false);
  assert.equal((await db.doc("wallets/fixture_inviter").get()).data().rothCredit, 5); assert.equal((await db.doc("wallets/fixture_referred").get()).data().rothCredit, 5);
 } finally {
ledger.recordRothMovement = original;
}
}));
test("Cloud Run completion reloads canonical timestamps and deduplicates all subscribers across transport retries", () => fixture("completion-canonical", async (db) => {
 const {processCompletion} = require("./completion-recovery-http"); const {buildDeliveryCompletedEvent} = require("./delivery-completed-event");
 await db.doc("deliveryRequests/job").set({status: "delivered", paymentStatus: "paid", senderId: "fixture_sender"}); await db.doc("users/fixture_sender").set({role: "fixture_only"});
 const event = buildDeliveryCompletedEvent({deliveryId: "job", delivery: {status: "delivered", paymentStatus: "paid", senderId: "fixture_sender", createdAt: new Date()}, completedAt: new Date()});
 await db.doc(`platformEvents/${event.eventId}`).set(event);
 const before = (await db.doc(`platformEvents/${event.eventId}`).get()).data();
 const first = await processCompletion(db, event.eventId); const retry = await processCompletion(db, event.eventId);
 assert.ok(first.results.every((r) => r.skipped === false)); assert.ok(retry.results.every((r) => r.skipped === true));
 assert.equal((await db.collection("platformEventSubscribers").get()).size, first.results.length);
 const projected = (await db.doc(`deliveryActivity/${event.eventId}`).get()).data(); assert.equal(projected.completedAt.toMillis(), before.completedAt.toMillis());
 assert.equal((await db.collection("walletTransactions").get()).size, 0); assert.equal((await db.collection("notifications").get()).size, 0);
 await assert.rejects(processCompletion(db, "delivery_completed_missing"), /invalid_canonical_completion/);
}));

test("completion retries preserve notification read state and immutable creation time after a crash", () => fixture("completion-record-crash", async (db) => {
 const {runSubscriber, subscribers} = require("./delivery-completed-event")._private;
 const event = {eventId: "delivery_completed_crash", deliveryId: "job", recipientId: "recipient"};
 await assert.rejects(runSubscriber(db, event, "recipient", async (...args) => {
 await subscribers.recipient(...args); throw new Error("crash_after_write");
 }), /crash_after_write/);
 const ref = db.doc("recipientNotifications/delivery_completed_crash"); const before = (await ref.get()).data();
 await ref.update({read: true}); await runSubscriber(db, event, "recipient", subscribers.recipient);
 const after = (await ref.get()).data(); assert.equal(after.read, true); assert.ok(after.createdAt.isEqual(before.createdAt)); assert.equal((await db.collection("recipientNotifications").get()).size, 1);
}));
test("completion projections preserve dispute and payment review holds", () => fixture("completion-review-holds", async (db) => {
 const {projectLinkedCompletion} = require("./delivery-completed-event")._private;
 await db.doc("deliveryRequests/job").set({status: "delivered", businessOrderId: "order", riderId: "rider"});
 const event = {eventId: "delivery_completed_review", deliveryId: "job", riderId: "rider", completedAt: new Date()};
 for (const hold of [{status: "under_review"}, {status: "disputed"}, {status: "accepted", underReview: true}, {status: "accepted", disputeOpen: true}, {status: "accepted", paymentInvestigation: true}]) {
 await db.doc("businessOrders/order").set({...hold, deliveryId: "job"}); await projectLinkedCompletion(db, event, "businessOrders", "order"); assert.deepEqual((await db.doc("businessOrders/order").get()).data(), {...hold, deliveryId: "job"});
 }
}));
