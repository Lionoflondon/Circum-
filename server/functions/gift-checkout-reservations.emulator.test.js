/* eslint-disable max-len, require-jsdoc */
const {test, before, after, mock} = require("node:test");
const assert = require("node:assert/strict");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {getAuth} = require("firebase-admin/auth");
const gifts = require("./gifts-payment");
const reservations = require("./gift-checkout-reservations");
let app; let db;
before(() => {
  assert(process.env.FIRESTORE_EMULATOR_HOST, "Emulator only");
  app = initializeApp({projectId: "demo-gift-reservations", storageBucket: "demo-gift-reservations.appspot.com"});
  db = getFirestore(); db.settings({ignoreUndefinedProperties: true});
  mock.method(getAuth(), "getUserByEmail", async (email) => ({email, uid: email.split("@")[0]}));
});
after(async () => {
mock.restoreAll(); await deleteApp(app);
});
function provider({loseResponse = false} = {}) {
  const objects = new Map(); const requests = new Map(); let lost = false;
  const create = async (params, options) => {
    assert(options.idempotencyKey);
    const key = options.idempotencyKey;
    if (requests.has(key)) assert.deepEqual(params, requests.get(key));
    else {
      requests.set(key, params);
      objects.set(key, {id: `cs_test_${objects.size}`, url: "https://example.invalid/test", currency: "gbp", amount_total: params.line_items[0].price_data.unit_amount, payment_status: "unpaid", status: "open", metadata: params.metadata});
    }
    if (loseResponse && !lost) {
lost = true; throw new Error("simulated response lost after provider creation");
}
    return objects.get(key);
  };
  const retrieve = async (id) => [...objects.values()].find((x) => x.id === id);
  const stripe = {checkout: {sessions: {create, retrieve, list: async () => ({data: [...objects.values()], has_more: false}), expire: async (id) => {
const s = await retrieve(id); s.status = "expired"; return s;
}}}};
  return {stripe, objects};
}
async function fixture(id, balance = 0) {
  const email = `${id}@example.invalid`; const context = {auth: {uid: id, token: {email}}, app: {appId: "test"}};
  await db.doc(`wallets/${email}`).set({uid: id, balance, rothCredit: balance});
  await db.doc(`senderWallets/${id}`).set({balance, rothCredit: balance});
  const data = {giftDraftId: id, giftDraft: {recipientName: "QA Recipient", deliveryAddress: "QA London address", grossGiftBudget: 50}, applyRoth: balance > 0, paymentMethod: "card"};
  return {data, context, email};
}
for (const callers of [2, 10]) {
  test(`${callers} concurrent Gift callers preserve one session, frozen split, debit and final Gift`, async () => {
    const id = `concurrent-${callers}`; const f = await fixture(id, 7); const p = provider();
    const results = await Promise.allSettled(Array.from({length: callers}, () => gifts.createGiftPayment(p.stripe).run(f.data, f.context)));
    assert.equal(results.filter((r) => r.status === "rejected").length, 0, JSON.stringify(results));
    assert.equal(p.objects.size, 1);
    const session = [...p.objects.values()][0]; assert.equal(session.amount_total, 4300);
    assert.equal((await db.doc(`wallets/${f.email}`).get()).data().balance, 0);
    assert.equal((await db.doc(`walletTransactions/gift_roth_${id}`).get()).data().amount, -7);
    session.payment_status = "paid"; session.status = "complete";
    await Promise.all(Array.from({length: 2}, () => gifts.finalizeGiftPayment(p.stripe).run({giftDraftId: id, sessionId: session.id}, f.context)));
    assert.equal((await db.collection("giftRequests").where("senderId", "==", id).get()).size, 1);
    assert.equal((await db.doc(`wallets/${f.email}`).get()).data().balance, 0);
    assert.equal((await db.doc(`giftCheckoutReservations/${reservations.idFor(id)}`).get()).data().status, "paid");
  });
}
test("unknown provider response retries the same identity and cannot release its Roth early", async () => {
  const f = await fixture("timeout", 7); const p = provider({loseResponse: true});
  await assert.rejects(gifts.createGiftPayment(p.stripe).run(f.data, f.context), /Stripe Checkout/);
  await assert.rejects(gifts.cancelGiftPayment(p.stripe).run({giftDraftId: "timeout"}, f.context), /unresolved/);
  await gifts.createGiftPayment(p.stripe).run(f.data, f.context);
  assert.equal(p.objects.size, 1);
  await Promise.all([1, 2].map(() => gifts.cancelGiftPayment(p.stripe).run({giftDraftId: "timeout"}, f.context)));
  assert.equal((await db.doc(`wallets/${f.email}`).get()).data().balance, 7);
  assert.equal((await db.doc("walletTransactions/release_gift_roth_timeout").get()).data().amount, 7);
  await assert.rejects(gifts.createGiftPayment(p.stripe).run(f.data, f.context), /ended/);
});
test("external-only and Roth-only preserve their original total and finalize once", async () => {
  for (const balance of [0, 50]) {
    const id = `funding-${balance}`; const f = await fixture(id, balance); const p = provider();
    const result = await gifts.createGiftPayment(p.stripe).run(f.data, f.context);
    if (balance === 0) {
assert.equal(p.objects.size, 1); assert.equal([...p.objects.values()][0].amount_total, 5000);
} else {
assert.equal(p.objects.size, 0); assert.equal(result.paymentStatus, "paid"); assert.equal((await db.doc(`wallets/${f.email}`).get()).data().balance, 0);
}
  }
});
test("foreign caller and changed Gift payload cannot reuse or mutate reservation", async () => {
  const f = await fixture("ownership"); const p = provider();
  await gifts.createGiftPayment(p.stripe).run(f.data, f.context);
  await assert.rejects(gifts.createGiftPayment(p.stripe).run(f.data, {auth: {uid: "other", token: {email: "other@example.invalid"}}}), /cannot be started/);
  await assert.rejects(gifts.createGiftPayment(p.stripe).run({...f.data, giftDraft: {...f.data.giftDraft, grossGiftBudget: 60}}, f.context), /changed/);
  assert.equal(p.objects.size, 1);
});
test("Stripe expiry replay releases only a terminal bound checkout", async () => {
  const f = await fixture("expiry", 7); const p = provider();
  await gifts.createGiftPayment(p.stripe).run(f.data, f.context);
  const session = [...p.objects.values()][0]; session.status = "expired";
  await gifts.handleGiftCheckoutExpired(p.stripe, session);
  await gifts.handleGiftCheckoutExpired(p.stripe, session);
  assert.equal((await db.doc(`wallets/${f.email}`).get()).data().balance, 7);
  await assert.rejects(gifts.finalizeGiftPaymentFromCheckoutSession({giftDraftId: "expiry", actorUid: "expiry", session: {...session, payment_status: "paid"}}), /ended/);
});
test("webhook finalization recovers a provider identity lost before Firestore persistence", async () => {
  const f = await fixture("webhook-response", 7); const p = provider({loseResponse: true});
  await assert.rejects(gifts.createGiftPayment(p.stripe).run(f.data, f.context));
  const session = [...p.objects.values()][0]; session.status = "complete"; session.payment_status = "paid";
  await gifts.finalizeGiftPaymentFromCheckoutSession({giftDraftId: f.data.giftDraftId, session});
  await gifts.finalizeGiftPaymentFromCheckoutSession({giftDraftId: f.data.giftDraftId, session});
  assert.equal((await db.doc(`giftRequests/${f.data.giftDraftId}`).get()).data().paymentStatus, "paid");
  assert.equal((await db.doc(`wallets/${f.email}`).get()).data().balance, 0);
});
test("untrusted draft protocol cannot bypass legacy provider reconciliation", async () => {
  const f = await fixture("forged-protocol"); const p = provider();
  await db.doc("giftPaymentDrafts/forged-protocol").set({senderId: "forged-protocol", senderEmail: f.email, giftCheckoutProtocol: 1, grossGiftBudget: 50, paymentStatus: "payment_pending"});
  await assert.rejects(gifts.createGiftPayment(p.stripe).run({giftDraftId: "forged-protocol"}, f.context), /reconciliation/);
  assert.equal(p.objects.size, 0);
});
test("native card, Apple Pay and Google Pay retries preserve one PaymentIntent", async () => {
  for (const method of ["card", "apple_pay", "google_pay"]) {
    const f = await fixture(`native-${method}`, 7); const objects = new Map(); const bodies = new Map();
    const stripe = {customers: {create: async () => ({id: "cus_qa"}), retrieve: async () => ({id: "cus_qa"})}, ephemeralKeys: {create: async () => ({secret: "emulator-only"})}, paymentIntents: {
      create: async (params, options) => {
        if (objects.has(options.idempotencyKey)) assert.deepEqual(bodies.get(options.idempotencyKey), params);
        else {
bodies.set(options.idempotencyKey, params); objects.set(options.idempotencyKey, {...params, id: `pi_test_${method}`, client_secret: "emulator-only", status: "requires_payment_method"});
}
        return objects.get(options.idempotencyKey);
      }, retrieve: async () => [...objects.values()][0],
    }};
    const data = {...f.data, checkoutMode: "payment_intent", paymentMethod: method};
    await Promise.all([1, 2].map(() => gifts.createGiftPayment(stripe).run(data, f.context)));
    assert.equal(objects.size, 1); assert.equal([...objects.values()][0].amount, 4300);
    const intent = {...[...objects.values()][0], status: "succeeded", amount_received: 4300};
    await gifts.handleGiftPaymentIntent(stripe, intent); await gifts.handleGiftPaymentIntent(stripe, intent);
    await gifts.handleGiftPaymentIntent(stripe, {...intent, status: "requires_payment_method"});
    assert.equal((await db.doc(`giftPaymentDrafts/native-${method}`).get()).exists, false);
    assert.equal((await db.doc(`wallets/${f.email}`).get()).data().balance, 0);
  }
});
test("campaign retries and request-key-free standard retries use one provider identity", async () => {
  const f = await fixture("campaign-retry", 0); const p = provider();
  const data = {source: "sender_mobile_campaign", campaignParticipant: {campaignId: "winter", campaignName: "Winter"}, grossGiftBudget: 50, paymentMethod: "card", returnOrigin: "https://circum.co.uk"};
  await Promise.all([1, 2].map(() => gifts.createGiftPayment(p.stripe).run(data, f.context)));
  assert.equal(p.objects.size, 1);
  const g = await fixture("no-request-key", 0); const q = provider();
  delete g.data.giftDraftId;
  if (g.data.giftDraft) delete g.data.giftDraft.giftDraftId;
  await Promise.all([1, 2].map(() => gifts.createGiftPayment(q.stripe).run(g.data, g.context)));
  assert.equal(q.objects.size, 1);
});
test("clients cannot forge checkout origin, reservation or reservation release", async () => {
  const {initializeTestEnvironment, assertFails} = require("@firebase/rules-unit-testing");
  const {doc, setDoc, updateDoc, deleteDoc} = require("firebase/firestore");
  const fs = require("node:fs"); const path = require("node:path");
  const env = await initializeTestEnvironment({projectId: "demo-gift-reservation-rules", firestore: {rules: fs.readFileSync(process.env.GIFT_TEST_RULES || path.join(__dirname, "../../firestore.rules"), "utf8")}});
  try {
    for (const collection of ["giftCheckoutOrigins", "giftCheckoutReservations", "walletTransactions"]) {
      await env.withSecurityRulesDisabled(async (context) => setDoc(doc(context.firestore(), collection, "protected"), {senderId: "customer", uid: "customer", status: "open"}));
      for (const uid of ["customer", "rider", "outsider"]) {
        const client = env.authenticatedContext(uid).firestore();
        await assertFails(setDoc(doc(client, collection, "forged"), {senderId: uid, uid, status: "paid"}));
        await assertFails(updateDoc(doc(client, collection, "protected"), {status: "released"}));
        await assertFails(deleteDoc(doc(client, collection, "protected")));
      }
    }
  } finally {
 await env.cleanup();
}
});
