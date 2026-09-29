/* eslint-disable max-len, require-jsdoc */
const {test, before, after} = require("node:test");
const assert = require("node:assert/strict");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {getAuth} = require("firebase-admin/auth");
const qaPublic = require("./qa-public-delivery");
const enabled = !!process.env.FIRESTORE_EMULATOR_HOST;
let app; let db;
before(() => {
if (enabled) {
app = initializeApp({projectId: "demo-special-qa"}); db = getFirestore();
}
});
after(async () => {
if (app) await deleteApp(app);
});
test("private canonical Health/Business checkouts are retry-safe, root-isolated and cleaned automatically (simulated provider)", {skip: !enabled}, async (t) => {
  process.env.GOOGLE_MAPS_DIRECTIONS_API_KEY = "emulator-only";
  t.mock.method(global, "fetch", async () => ({ok: true, json: async () => ({routes: [{distanceMeters: 1609.344}]})}));
  t.mock.method(getAuth(), "verifyIdToken", async () => ({uid: "qa_sender", email: "qa@example.invalid"}));
  t.mock.method(getAuth(), "getUserByEmail", async (email) => ({uid: "qa_sender", email}));
  const objects = new Map(); const intents = new Map(); const refunds = []; let calls = 0;
  const stripe = {checkout: {sessions: {
    async create(params, options) {
if (!objects.has(options.idempotencyKey)) {
calls++; objects.set(options.idempotencyKey, {id: `cs_test_${calls}`, url: "https://example.invalid/qa", currency: "gbp", livemode: false, amount_total: params.line_items[0].price_data.unit_amount, metadata: params.metadata, status: "open", payment_status: "unpaid"});
} return objects.get(options.idempotencyKey);
},
    async retrieve(id) {
return [...objects.values()].find((o) => o.id === id);
},
    async expire(id) {
const o = await this.retrieve(id); o.status = "expired"; return o;
},
  }}, paymentIntents: {
    async create(input, options) {
      if (!intents.has(options.idempotencyKey)) intents.set(options.idempotencyKey, {id: `pi_test_${intents.size + 1}`, livemode: false, status: "succeeded", amount: input.amount, amount_received: input.amount, currency: input.currency, metadata: input.metadata});
      return intents.get(options.idempotencyKey);
    },
    async retrieve(id) {
return [...intents.values()].find((o) => o.id === id);
},
  }, refunds: {
    async create(input) {
const row = {id: `re_test_${refunds.length + 1}`, livemode: false, status: "succeeded", ...input}; refunds.push(row); return row;
},
    async list({payment_intent: id}) {
return {data: refunds.filter((r) => r.payment_intent === id)};
},
  }};
  const env = {GCLOUD_PROJECT: "circum-2797c", STRIPE_MODE: "TEST", STRIPE_SECRET_KEY: "sk_test_fixture", CIRCUM_QA_STRIPE_SECRET_KEY: "sk_test_fixture", QA_LIFECYCLE_ENABLED: "true", QA_LIFECYCLE_ALLOWLIST: JSON.stringify({operators: ["qa_operator"], senders: ["qa_sender"], riders: ["qa_rider"]})};
  const f = require("./qa-special-flow")._test.factory({db, env, stripe});
  const ctx = {auth: {uid: "qa_sender", token: {email: "qa@example.invalid"}}, app: {appId: "emulator"}, rawRequest: {headers: {authorization: "Bearer test"}}};
  await assert.rejects(f.handle({action: "prepare", requestId: "lifecycle_a"}, {...ctx, app: undefined}), /attestation/);
  await assert.rejects(f.handle({action: "prepare", requestId: "lifecycle_a"}, {...ctx, auth: {uid: "outsider"}}), /not permitted/);
  const operator = {...ctx, auth: {uid: "qa_operator", token: {email: "operator@example.invalid"}}};
  const {fixtureId} = await f.handle({action: "prepare", requestId: "lifecycle_a"}, operator);
  const handle = (data, actor = ctx) => f.handle({...data, fixtureId}, actor);
  const pagination = await handle({action: "activity_pagination_seed"});
  assert.equal(pagination.count, 101);
  assert.notEqual(pagination.firstPageExpectedId, pagination.secondPageExpectedId);
  const walletNotification = await handle({action: "wallet_notification_seed"});
  assert.equal(walletNotification.destinationRoute, "wallet");
  const chatProbe = await handle({action: "chat_retry_probe"});
  assert.equal(chatProbe.exactlyOnce, true);
  assert.equal(chatProbe.stored, 1);
  const cancellationProbe = await handle({action: "cancellation_quote_probe"});
  assert.deepEqual(cancellationProbe.sensitiveKeysPresent, []);
  assert.equal(cancellationProbe.quote.canCancel, true);
  await assert.rejects(handle({action: "roth", scenario: "prepare"}, operator), /QA Sender required/);
  assert.equal((await handle({action: "roth", scenario: "prepare"})).balance, 57);
  assert.equal((await handle({action: "roth", scenario: "roth_only"})).rothApplied, 50);
  assert.equal((await handle({action: "roth", scenario: "roth_only"})).idempotent, true);
  assert.equal((await handle({action: "roth", scenario: "split"})).cardAmount, 43);
  assert.equal((await handle({action: "roth", scenario: "split"})).idempotent, true);
  assert.equal((await handle({action: "roth", scenario: "insufficient"})).balanceUnchanged, true);
  assert.equal((await handle({action: "roth", scenario: "read"})).completedDebits, 2);
  assert.equal((await handle({action: "roth", scenario: "reconcile"})).errors, 0);
  assert.equal((await handle({action: "roth", scenario: "reconcile"})).effective, 0);
  const irisFirst = await handle({action: "iris", scenario: "photo"});
  const irisReplay = await handle({action: "iris", scenario: "photo"});
  assert.equal(irisFirst.idempotent, false);
  assert.equal(irisReplay.idempotent, true);
  assert.equal(irisFirst.photo.analysisId, irisReplay.photo.analysisId);
  assert.equal(irisFirst.photo.imageHash, undefined);
  assert.equal((await db.doc(`qaSpecialFlowFixtures/${fixtureId}/irisPhotoAnalyses/${irisFirst.photo.analysisId}`).get()).data().isSyntheticQa, true);
  assert.ok((await handle({action: "iris", scenario: "weed"})).iris);
  await assert.rejects(handle({action: "iris", scenario: "unknown"}), /Unknown synthetic IRIS scenario/);
  await assert.rejects(handle({action: "iris", scenario: "small"}, operator), /QA Sender required/);
  const fixture = (await db.doc(`qaSpecialFlowFixtures/${fixtureId}`).get()).data();
  assert.equal(fixture.senderId, "qa_sender");
  assert.equal((await db.doc(`qaSpecialFlowFixtures/${fixtureId}/businessAccounts/qa_business`).get()).data().ownerUid, "qa_sender");
  const h = await handle({action: "health"}); const h2 = await handle({action: "health"});
  assert.equal(h.bookingId, h2.bookingId); assert.equal(h.sessionId, h2.sessionId); assert.equal(h.routeAuthority, 2); assert(h.amountPence > 0);
  const hp = await handle({action: "health_finalize"}); const hp2 = await handle({action: "health_finalize"});
  assert.equal(hp.providerId, hp2.providerId); assert.equal((await db.doc(`qaSpecialFlowFixtures/${fixtureId}/deliveryRequests/${hp.deliveryId}`).get()).data().serviceType, "HEALTH_PLUS");
  const b = await handle({action: "business"}); const b2 = await handle({action: "business"});
  assert.equal(b.sessionId, b2.sessionId); assert.equal(b.reservationId, b2.reservationId); assert.equal(b.cardAmount, 5); assert.equal(b.rothApplied, 0); assert.equal(calls, 2);
  const bp = await handle({action: "business_finalize"}); const bp2 = await handle({action: "business_finalize"});
  assert.equal(bp.providerId, bp2.providerId); assert.equal((await db.doc(`qaSpecialFlowFixtures/${fixtureId}/deliveryRequests/${bp.deliveryId}`).get()).data().serviceType, "business");
  await handle({action: "book", delivery: "c", profile: "scheduled", scheduledOffsetMs: 1000});
  const scheduledPay = await handle({action: "pay", delivery: "c"}); assert.equal(scheduledPay.providerSimulation, false);
  const rider = {...ctx, auth: {uid: "qa_rider", token: {}}}; await handle({action: "accept", delivery: "c"}, rider);
  await assert.rejects(handle({action: "start_heading_to_pickup", delivery: "c"}, rider), /not ready/);
  await new Promise((resolve) => setTimeout(resolve, 1100)); await handle({action: "start_heading_to_pickup", delivery: "c"}, rider);
  assert.deepEqual(await handle({action: "seed_legacy_status", delivery: "c", legacyStatus: "en_route_to_pickup"}, operator), {idempotent: false, normalizedStatus: "navigating_to_pickup"});
  assert.deepEqual(await handle({action: "seed_legacy_status", delivery: "c", legacyStatus: "en_route_to_pickup"}, operator), {idempotent: true, normalizedStatus: "navigating_to_pickup"});
  await handle({action: "arrived_at_pickup", delivery: "c"}, rider);
  await handle({action: "send_message", delivery: "c", message: "Synthetic scheduled handover"}, rider);
  await handle({action: "book", delivery: "d", profile: "vanguard"}); await handle({action: "pay", delivery: "d"}); await handle({action: "accept", delivery: "d"}, rider);
  await assert.rejects(handle({action: "seed_legacy_status", delivery: "d", legacyStatus: "rider_assigned"}, rider), /Wrong QA actor/);
  await assert.rejects(handle({action: "seed_legacy_status", delivery: "d", legacyStatus: "arbitrary"}, operator), /reviewed legacy/);
  await assert.rejects(handle({action: "seed_legacy_status", delivery: "d", legacyStatus: "__proto__"}, operator), /reviewed legacy/);
  assert.deepEqual(await handle({action: "seed_legacy_status", delivery: "d", legacyStatus: "rider_assigned"}, operator), {idempotent: false, normalizedStatus: "accepted"});
  await handle({action: "start_heading_to_pickup", delivery: "d"}, rider);
  await assert.rejects(handle({action: "seed_legacy_status", delivery: "d", legacyStatus: "rider_assigned"}, operator), /out of order/);
  const riderRead = await handle({action: "read", delivery: "d"}, rider);
  assert.equal(riderRead.records.deliveryRequests.find((d) => d.id.endsWith("_d")).trustPointsAwarded, 4);
  await handle({action: "book", delivery: "a", profile: "standard"}); await handle({action: "pay", delivery: "a"}); await handle({action: "accept", delivery: "a"}, rider);
  const location = (clientRecordedAt) => ({latitude: 51.5, longitude: -0.12, accuracyMeters: 8, clientRecordedAt});
  assert.equal((await handle({action: "publish_location", delivery: "a", status: "completed", location: location(1000)}, rider)).status, "accepted");
  await handle({action: "start_heading_to_pickup", delivery: "a"}, rider);
  assert.equal((await handle({action: "publish_location", delivery: "a", status: "accepted", location: location(2000)}, rider)).status, "navigating_to_pickup");
  assert.deepEqual(await handle({action: "publish_location", delivery: "a", status: "accepted", location: location(1000)}, rider), {status: "navigating_to_pickup", staleCoordinate: true, statusFromClientIgnored: true});
  await handle({action: "arrived_at_pickup", delivery: "a"}, rider);
  await handle({action: "verify_collection_pin", delivery: "a", pin: "2468"}, rider);
  await handle({action: "confirm_collected", delivery: "a"}, rider);
  assert.equal((await handle({action: "publish_location", delivery: "a", status: "accepted", location: location(3000)}, rider)).status, "collected");
  await handle({action: "start_delivery", delivery: "a"}, rider);
  assert.equal((await handle({action: "publish_location", delivery: "a", status: "accepted", location: location(4000)}, rider)).status, "navigating_to_dropoff");
  await handle({action: "arrived_at_dropoff", delivery: "a"}, rider);
  assert.equal((await handle({action: "publish_location", delivery: "a", status: "accepted", location: location(5000)}, rider)).status, "arrived_at_dropoff");
  await handle({action: "verify_receiver_pin", delivery: "a", pin: "8642"}, rider);
  await assert.rejects(handle({action: "publish_location", delivery: "a", status: "accepted", location: location(6000)}, rider), /not active/);
  const afterLocation = await handle({action: "read"}, rider);
  assert.equal(afterLocation.records.activeDeliveries.find((d) => d.id.endsWith("_a")).status, "arrived_at_dropoff");
  assert.equal(afterLocation.records.deliveryRequests.find((d) => d.id.endsWith("_a")).status, "completed");
  for (const name of ["prescriptionPickups", "healthPlusProfiles", "businessInvoices", "notifications", "deliveryRequests", "walletTransactions"]) assert.equal((await db.collection(name).get()).size, 0, name);
  await db.doc(`qaSpecialFlowFixtures/${fixtureId}`).update({expiresAt: require("firebase-admin/firestore").Timestamp.fromMillis(1)});
  assert.deepEqual(await f.expire(), {processed: 1});
  assert([...objects.values()].every((o) => o.status === "expired"));
  assert.equal(refunds.length, intents.size);
  assert.equal((await db.doc(`qaSpecialFlowFixtures/${fixtureId}`).get()).data().archived, true);
  await assert.rejects(handle({action: "health"}), /expired/);
  const second = await f.handle({action: "prepare", requestId: "lifecycle_b"}, operator);
  assert.notEqual(second.fixtureId, fixtureId);
  await f.handle({action: "book", fixtureId: second.fixtureId, delivery: "a"}, ctx);
  const publicCreated = await f.handle({action: "public_delivery", fixtureId: second.fixtureId}, ctx);
  const publicDoc = await db.doc(`deliveryRequests/${publicCreated.deliveryId}`).get();
  assert.equal(publicDoc.data().isSyntheticQa, true);
  assert.equal(publicDoc.data().realDispatch, false);
  assert.equal(publicDoc.data().excludeFromSettlement, true);
  const publicFixture = (await db.doc(`qaSpecialFlowFixtures/${second.fixtureId}`).get()).data();
  const access = await qaPublic.activeFixtureForRider(db, {...ctx, auth: {uid: "not_allowlisted"}}, env);
  assert.equal(access, null);
  const riderAccess = await qaPublic.authorizePublicDelivery(db, {...ctx, auth: {uid: "qa_rider"}}, publicCreated.deliveryId, env);
  assert.equal(riderAccess.uid, "qa_rider");
  const offer = await qaPublic.getPublicOffer({db, access: {uid: "qa_rider", fixture: publicFixture}, projection: require("./rider-offers").projection});
  assert.equal(offer.eligible, true);
  assert.equal(offer.nearestRequests.length, 1);
  assert.equal(offer.nearestRequests[0].pickupLocality, "QA pickup locality");
  assert.equal(offer.nearestRequests[0].riderEarning, 13);
  await assert.rejects(qaPublic.authorizePublicDelivery(db, {...ctx, auth: {uid: "not_allowlisted"}}, publicCreated.deliveryId, env), /not permitted/);
  const accepted = await qaPublic.accept({db, context: {...ctx, auth: {uid: "qa_rider"}}, deliveryId: publicCreated.deliveryId, env});
  assert.equal(accepted.qaOnly, true);
  assert.equal((await qaPublic.accept({db, context: {...ctx, auth: {uid: "qa_rider"}}, deliveryId: publicCreated.deliveryId, env})).idempotent, true);
  await assert.rejects(qaPublic.transition({db, context: {...ctx, auth: {uid: "qa_rider"}}, deliveryId: publicCreated.deliveryId, action: "verify_collection_pin", pin: "0000", env}), /incorrect/);
  for (const [action, pin] of [["start_heading_to_pickup"], ["arrived_at_pickup"], ["verify_collection_pin", "2468"], ["confirm_collected"], ["start_delivery"], ["arrived_at_dropoff"], ["verify_receiver_pin", "8642"]]) {
    await qaPublic.transition({db, context: {...ctx, auth: {uid: "qa_rider"}}, deliveryId: publicCreated.deliveryId, action, pin, env});
  }
  assert.equal((await db.doc(`deliveryRequests/${publicCreated.deliveryId}`).get()).data().status, "delivered");
  assert.equal((await db.collection("riderEarningTransactions").where("deliveryId", "==", publicCreated.deliveryId).get()).empty, true);
  await f.handle({action: "cleanup", fixtureId: second.fixtureId}, operator);
  assert.equal((await db.doc(`deliveryRequests/${publicCreated.deliveryId}`).get()).exists, false);
});
