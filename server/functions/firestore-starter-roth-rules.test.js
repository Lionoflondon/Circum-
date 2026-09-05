/* eslint-disable max-len, require-jsdoc */
const {test, before, after, mock} = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {getAuth} = require("firebase-admin/auth");
const {initializeTestEnvironment, assertFails, assertSucceeds} = require("@firebase/rules-unit-testing");
const {doc, setDoc, updateDoc, deleteField} = require("firebase/firestore");
const account = require("./sender-account");
const ledger = require("./roth-ledger");
const {walletIdForEmail} = require("./wallet-core");
const projectId = "demo-starter-roth";
const authority = {
  starterRothGrantStatus: "pending",
  starterRothGrantedAt: new Date("2026-01-01"),
  starterRothAmount: 5,
  starterRothTransactionId: "forged",
};
let app; let db; let env; let sequence = 0;

before(async () => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, "Firestore emulator required");
  app = initializeApp({projectId});
  db = getFirestore();
  db.settings({ignoreUndefinedProperties: true});
  mock.method(getAuth(), "getUserByEmail", async (email) => ({uid: email.split("@")[0], email}));
  env = await initializeTestEnvironment({projectId, firestore: {
    rules: fs.readFileSync(process.env.STARTER_ROTH_RULES_FILE || path.join(__dirname, "../../firestore.rules"), "utf8"),
  }});
});
after(async () => {
  mock.restoreAll();
  if (env) await env.cleanup();
  if (app) await deleteApp(app);
});

function fixture() {
  const uid = `starter-${++sequence}`;
  const email = `${uid}@example.invalid`;
  return {uid, email, ref: db.doc(`users/${uid}`),
    client: env.authenticatedContext(uid).firestore(),
    context: {auth: {uid, token: {email}}}};
}

async function assertGrant(f) {
  const profile = (await f.ref.get()).data();
  const wallet = (await db.doc(`wallets/${walletIdForEmail(f.email)}`).get()).data();
  const projection = (await db.doc(`senderWallets/${f.uid}`).get()).data();
  const tx = (await db.doc(`walletTransactions/sender_welcome_roth_${f.uid}`).get()).data();
  assert.equal(profile.starterRothGrantStatus, "granted");
  assert.equal(wallet.balance, 5);
  assert.equal(wallet.rothCredit, 5);
  assert.equal(projection.balance, 5);
  assert.equal(tx.amount, 5);
  assert.equal(tx.type, ledger.TRANSACTION_TYPES.promotionalReward);
  assert.equal(tx.idempotencyKey, `sender_welcome_roth:${f.uid}`);
  assert.equal((await db.collection("walletTransactions").where("uid", "==", f.uid).get()).size, 1);
}

test("customer cannot create, modify, remove or replace any starter-Roth authority field", async () => {
  for (const [field, value] of Object.entries(authority)) {
    const f = fixture();
    const ref = doc(f.client, "users", f.uid);
    await assertFails(setDoc(ref, {displayName: "Customer", [field]: value}));
    await f.ref.set({displayName: "Customer"});
    await assertFails(updateDoc(ref, {[field]: value}));
    await f.ref.set(authority, {merge: true});
    await assertFails(updateDoc(ref, {[field]: typeof value === "number" ? 10 : "changed"}));
    await assertFails(updateDoc(ref, {[field]: deleteField()}));
    await assertFails(setDoc(ref, {displayName: "Replacement"}));
  }
});

test("legitimate self profile editing and Admin/backend authority remain available", async () => {
  const f = fixture();
  const ref = doc(f.client, "users", f.uid);
  await assertSucceeds(setDoc(ref, {role: "user", displayName: "Original"}));
  await f.ref.set(authority, {merge: true});
  await assertSucceeds(updateDoc(ref, {displayName: "Edited", phone: "+447700900001"}));
  assert.equal((await f.ref.get()).data().starterRothGrantStatus, "pending");
  const admin = env.authenticatedContext("finance-admin", {adminRole: "finance_admin"}).firestore();
  await assertSucceeds(updateDoc(doc(admin, "users", f.uid), {starterRothGrantStatus: "granted"}));
  const newProfile = fixture();
  await assertSucceeds(setDoc(doc(admin, "users", newProfile.uid), authority));
});

test("existing users cannot forge pending eligibility through Firestore or callable payloads", async () => {
  for (const profile of [{role: "user"}, {role: "customer"}, {roles: ["sender"], accountType: "sender"}]) {
    const f = fixture();
    await f.ref.set(profile);
    await assertFails(updateDoc(doc(f.client, "users", f.uid), {starterRothGrantStatus: "pending"}));
    await account.ensureSenderAccount.run(authority, f.context);
    await account.updateSenderProfile.run({...authority, displayName: "Legitimate edit"}, f.context);
    await ledger.initialiseSenderWallet.run(authority, f.context);
    await ledger.getSenderWallet.run(authority, f.context);
    assert.equal((await db.doc(`senderWallets/${f.uid}`).get()).data().balance, 0);
    assert.equal((await db.doc(`walletTransactions/sender_welcome_roth_${f.uid}`).get()).exists, false);
  }
});

test("new profiles receive exactly one grant across all entrypoints and concurrent retries", async () => {
  for (const first of ["ensureSenderAccount", "updateSenderProfile"]) {
    const f = fixture();
    await Promise.all(Array.from({length: 6}, () => account[first].run({displayName: "New Sender"}, f.context)));
    await account.ensureSenderAccount.run({}, f.context);
    await account.updateSenderProfile.run({}, f.context);
    await ledger.initialiseSenderWallet.run({}, f.context);
    await ledger.getSenderWallet.run({}, f.context);
    await assertFails(updateDoc(doc(f.client, "users", f.uid), {starterRothGrantStatus: "pending"}));
    await assertGrant(f);
  }
});

test("all four entrypoints repair backend-created pending grants once", async () => {
  for (const name of ["ensureSenderAccount", "updateSenderProfile", "initialiseSenderWallet", "getSenderWallet"]) {
    const f = fixture();
    await f.ref.set({roles: ["sender"], starterRothGrantStatus: "pending"});
    const fn = account[name] || ledger[name];
    await fn.run({}, f.context);
    await fn.run({}, f.context);
    await assertGrant(f);
  }
});

test("ledger success followed by interrupted profile marking repairs without a second credit", async () => {
  const f = fixture();
  await f.ref.set({roles: ["sender"], starterRothGrantStatus: "pending"});
  await ledger.grantSenderWelcomeRoth({uid: f.uid, email: f.email, source: "interrupted_test"});
  assert.equal((await f.ref.get()).data().starterRothGrantStatus, "pending");
  await ledger.getSenderWallet.run({}, f.context);
  await account.ensureSenderAccount.run({}, f.context);
  await assertGrant(f);
});
