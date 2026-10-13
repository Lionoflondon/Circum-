/* eslint-disable max-len, require-jsdoc */
"use strict";
const {test, before, after, mock} = require("node:test");
const assert = require("node:assert/strict");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {getAuth} = require("firebase-admin/auth");
const {createWebsiteRoth} = require("./website-roth");
const {walletIdForEmail} = require("./wallet-core");
let app; let db; let service; let sent; let session; let milliseconds = 100000;
const alice = {uid: "roth_test_alice", email: "alice@example.invalid"};
const bob = {uid: "roth_test_bob", email: "bob@example.invalid"};
before(async () => {
  assert(process.env.FIRESTORE_EMULATOR_HOST, "Local emulator required");
  app = initializeApp({projectId: `demo-roth-test-${process.pid}`}); db = getFirestore();
  const users = [alice, bob];
  mock.method(getAuth(), "getUser", async (id) => users.find((u) => u.uid === id));
  mock.method(getAuth(), "getUserByEmail", async (email) => {
const u = users.find((v) => v.email === email); if (!u) throw Object.assign(new Error("missing"), {code: "auth/user-not-found"}); return u;
});
  await db.collection("users").doc(alice.uid).set({username: "alice"});
  await db.collection("users").doc(bob.uid).set({username: "bob"});
  await db.collection("wallets").doc(walletIdForEmail(bob.email)).set({rothCredit: 19});
  const stripe = {checkout: {sessions: {create: async (input) => {
    session = {id: "cs_test_website_roth", status: "complete", livemode: false, ...input, currency: "gbp", amount_total: input.line_items[0].price_data.unit_amount, payment_intent: "pi_test_roth", payment_status: "unpaid", url: "https://checkout.stripe.com/test"}; return session;
  }, retrieve: async () => session}}};
  service = createWebsiteRoth({db, auth: getAuth(), stripe, secret: "local-only-test-secret-never-for-production", now: () => milliseconds,
    sendCode: async (item) => {
sent = item;
}, credit: (args) => require("./roth-ledger").recordRothMovement({...args, db})});
});
after(async () => {
mock.restoreAll(); await deleteApp(app);
});
test("verified email binds payment to Alice; Bob unchanged; unpaid and tampered payments rejected; duplicate credits prevented", async () => {
  const challenge = await service.request({identifier: " ALICE@EXAMPLE.INVALID "}, "client1");
  assert.equal(sent.email, alice.email);
  await assert.rejects(service.verify({...challenge, code: "000000"}));
  const access = await service.verify({...challenge, code: sent.code});
  await assert.rejects(service.verify({...challenge, code: sent.code}), /invalid or expired/);
  await service.checkout({...access, amountPence: 100, uid: bob.uid, email: bob.email});
  assert.equal(session.client_reference_id, walletIdForEmail(alice.email));
  await assert.rejects(service.finalize(session));
  await assert.rejects(service.finalize({...session, payment_status: "paid", amount_total: 9900}), /amount/);
  await assert.rejects(service.finalize({...session, payment_status: "paid", client_reference_id: walletIdForEmail(bob.email)}), /match/);
  await assert.rejects(service.finalize({...session, payment_status: "paid", livemode: true}), /match/);
  session.payment_status = "paid"; session.status = "complete";
  assert.equal((await service.status(access)).status, "pending");
  assert.equal((await db.collection("walletTransactions").where("uid", "==", alice.uid).get()).size, 0);
  await Promise.all([service.finalize(session), service.finalize(session)]);
  assert.equal((await service.status(access)).balance, 1);
  assert.equal((await service.wallet(access)).balance, 1);
  await assert.rejects(service.wallet({...access, token: "a".repeat(64)}));
  await service.logout(access);
  await assert.rejects(service.wallet(access));
  const loginChallenge = await service.request({identifier: alice.email}, "returning-client");
  const login = await service.verify({...loginChallenge, code: sent.code});
  assert.equal((await service.wallet(login)).balance, 1);
  process.env.STRIPE_MODE = "test";
  await require("./roth-ledger").recordWebsiteRothTopUpFromStripeSession(session);
  const wallet = (await db.collection("wallets").doc(walletIdForEmail(alice.email)).get()).data();
  assert.equal(wallet.rothCredit, 1);
  assert.equal((await db.collection("senderWallets").doc(alice.uid).get()).data().balance, 1);
  assert.equal((await db.collection("wallets").doc(walletIdForEmail(bob.email)).get()).data().rothCredit, 19);
  assert.equal((await db.collection("walletTransactions").where("uid", "==", alice.uid).get()).size, 1);
  const emails = await db.collection("emailQueue").where("recipientId", "==", alice.uid).get();
  assert.equal(emails.size, 1);
  assert.equal(emails.docs[0].data().to, alice.email);
  assert.match(emails.docs[0].data().text, /1 ROTH/);
  assert.match(emails.docs[0].data().text, /website_roth_cs_test_website_roth/);
  assert.match(emails.docs[0].data().html, /circum_wordmark/);
  assert.doesNotMatch(emails.docs[0].data().html, /000000|verification code/);
  await assert.rejects(service.finalize({...session, payment_status: "unpaid", status: "expired"}));
  assert.equal((await db.collection("wallets").doc(walletIdForEmail(alice.email)).get()).data().rothCredit, 1);
  assert.equal((await db.collection("emailQueue").where("recipientId", "==", alice.uid).get()).size, 1);
});
test("username resolves server-side; wrong codes lock out; expiry rejects; unknown account does not send", async () => {
  const challenge = await service.request({identifier: "@bob"}, "client2");
  assert.equal(sent.uid, bob.uid);
  const correct = sent.code;
  for (let i = 0; i < 5; i++) await assert.rejects(service.verify({...challenge, code: "000000"}));
  await assert.rejects(service.verify({...challenge, code: correct}));
  const next = await service.request({identifier: "bob@example.invalid"}, "client3");
  milliseconds += 600001;
  await assert.rejects(service.verify({...next, code: sent.code}));
  sent = null;
  const unknown = await service.request({identifier: "missing@example.invalid"}, "client4");
  assert.equal(typeof unknown.challengeId, "string"); assert.equal(sent, null);
});

test("failure after committed credit retries without another ledger entry or receipt", async () => {
  const {finalizeWebsiteRoth} = require("./website-roth");
  const id = "b".repeat(64);
  await db.collection("websiteRothOrders").doc(id).set({uid: alice.uid, email: alice.email, walletId: walletIdForEmail(alice.email), amountPence: 100, sessionId: "cs_test_retry", status: "pending"});
  const paid = {id: "cs_test_retry", status: "complete", livemode: false, mode: "payment", payment_status: "paid", currency: "gbp", amount_total: 100, payment_intent: "pi_test_retry", client_reference_id: walletIdForEmail(alice.email), metadata: {type: "website_roth_top_up", orderId: id}};
  let failOnce = true;
  const credit = async (args) => {
    await require("./roth-ledger").recordRothMovement({...args, db});
    if (failOnce) {
 failOnce = false; throw new Error("temporary failure after credit");
}
  };
  const finalize = (value) => finalizeWebsiteRoth({db, auth: getAuth(), credit, live: false}, value);
  await assert.rejects(finalize(paid), /temporary failure/);
  assert.equal((await db.collection("emailQueue").doc("website_roth_receipt_cs_test_retry").get()).exists, false);
  await Promise.all([finalize(paid), finalize(paid)]);
  await assert.rejects(finalize({...paid, payment_status: "unpaid", status: "expired"}));
  assert.equal((await db.collection("wallets").doc(walletIdForEmail(alice.email)).get()).data().rothCredit, 2);
  assert.equal((await db.collection("walletTransactions").where("uid", "==", alice.uid).get()).size, 2);
  assert.equal((await db.collection("emailQueue").where("recipientId", "==", alice.uid).get()).size, 2);
  assert.equal((await db.collection("wallets").doc(walletIdForEmail(bob.email)).get()).data().rothCredit, 19);
});

test("named TEST ledger cannot change default production financial collections", async () => {
  const testDb = getFirestore(app, "roth-website-test");
  const productionBefore = (await db.collection("wallets").doc(walletIdForEmail(alice.email)).get()).data().rothCredit;
  await require("./roth-ledger").recordRothMovement({db: testDb, userId: walletIdForEmail(alice.email), userEmail: alice.email, uid: alice.uid, amount: 1, balanceType: "rothCredit", type: require("./roth-ledger-core").TRANSACTION_TYPES.userTopUp, reason: "Isolated TEST", transactionId: "isolated_named_test"});
  assert.equal((await testDb.collection("wallets").doc(walletIdForEmail(alice.email)).get()).data().rothCredit, 1);
  assert.equal((await db.collection("wallets").doc(walletIdForEmail(alice.email)).get()).data().rothCredit, productionBefore);
  assert.equal((await db.collection("walletTransactions").doc("isolated_named_test").get()).exists, false);
});
