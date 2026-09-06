/* eslint-disable max-len, require-jsdoc */
const {test, before, after} = require("node:test");
const assert = require("node:assert/strict");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {getAuth} = require("firebase-admin/auth");
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
  const objects = new Map(); let calls = 0;
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
  }}};
  const env = {GCLOUD_PROJECT: "circum-2797c", STRIPE_MODE: "TEST", STRIPE_SECRET_KEY: "sk_test_fixture", QA_LIFECYCLE_ENABLED: "true", QA_LIFECYCLE_ALLOWLIST: JSON.stringify({operators: ["qa_sender"], senders: ["qa_sender"], riders: ["qa_rider"]})};
  const f = require("./qa-special-flow")._test.factory({db, env, stripe});
  const ctx = {auth: {uid: "qa_sender", token: {email: "qa@example.invalid"}}, app: {appId: "emulator"}, rawRequest: {headers: {authorization: "Bearer test"}}};
  await assert.rejects(f.handle({action: "prepare"}, {...ctx, app: undefined}), /attestation/);
  await assert.rejects(f.handle({action: "prepare"}, {...ctx, auth: {uid: "outsider"}}), /not permitted/);
  const {fixtureId} = await f.handle({action: "prepare"}, ctx);
  const h = await f.handle({action: "health"}, ctx); const h2 = await f.handle({action: "health"}, ctx);
  assert.equal(h.bookingId, h2.bookingId); assert.equal(h.sessionId, h2.sessionId); assert.equal(h.routeAuthority, 2); assert(h.amountPence > 0);
  const b = await f.handle({action: "business"}, ctx); const b2 = await f.handle({action: "business"}, ctx);
  assert.equal(b.sessionId, b2.sessionId); assert.equal(b.reservationId, b2.reservationId); assert.equal(b.cardAmount, 5); assert.equal(b.rothApplied, 0); assert.equal(calls, 2);
  for (const name of ["prescriptionPickups", "healthPlusProfiles", "businessInvoices", "notifications", "deliveryRequests", "walletTransactions"]) assert.equal((await db.collection(name).get()).size, 0, name);
  await db.doc(`qaSpecialFlowFixtures/${fixtureId}`).update({expiresAt: require("firebase-admin/firestore").Timestamp.fromMillis(1)});
  assert.deepEqual(await f.expire(), {processed: 1});
  assert([...objects.values()].every((o) => o.status === "expired"));
  assert.equal((await db.doc(`qaSpecialFlowFixtures/${fixtureId}`).get()).data().archived, true);
  await assert.rejects(f.handle({action: "health"}, ctx), /expired/);
});
