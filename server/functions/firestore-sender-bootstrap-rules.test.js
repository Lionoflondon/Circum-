/* eslint-disable max-len, require-jsdoc */
const {test, before, after, mock} = require("node:test");
const assert = require("node:assert/strict");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {getAuth} = require("firebase-admin/auth");
const account = require("./sender-account");
const ledger = require("./roth-ledger");
const booking = require("./sender-booking");
let app; let db;
before(() => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST);
  app = initializeApp({projectId: "demo-sender-bootstrap"}); db = getFirestore(); db.settings({ignoreUndefinedProperties: true});
  mock.method(getAuth(), "getUserByEmail", async (email) => ({uid: email.split("@")[0], email}));
});
after(async () => {
mock.restoreAll(); if (app) await deleteApp(app);
});

test("checking central account authority resumes interrupted setup before web balance reads, without a second grant", async () => {
  const ctx = {auth: {uid: "recover", token: {email: "recover@example.invalid"}}};
  const grant = mock.method(ledger, "grantSenderWelcomeRoth", async () => {
throw new Error("temporary setup failure");
});
  await assert.rejects(account.updateSenderProfile.run({firstName: "Sender"}, ctx), /temporary setup failure/);
  grant.mock.restore();
  assert.equal((await db.doc("users/recover").get()).data().starterRothGrantStatus, "pending");
  for (let retry = 0; retry < 3; retry++) {
    assert.equal((await account.ensureSenderAccount.run({}, ctx)).allowed, true);
    assert.equal((await booking.getSenderRothBalance.run({}, ctx)).balance, 5);
  }
  assert.equal((await db.collection("walletTransactions").where("uid", "==", "recover").get()).size, 1);
  assert.equal((await db.doc("users/recover").get()).data().starterRothGrantStatus, "granted");
});

test("central bootstrap denies Rider-only identities and leaves legacy Sender credit unchanged", async () => {
  await db.doc("riderProfiles/rider").set({status: "active"});
  const rider = await account.ensureSenderAccount.run({}, {auth: {uid: "rider", token: {}}});
  assert.equal(rider.allowed, false);
  assert.equal((await db.doc("users/rider").get()).exists, false);
  await db.doc("users/legacy").set({role: "user", roles: ["sender"]});
  const ctx = {auth: {uid: "legacy", token: {email: "legacy@example.invalid"}}};
  assert.equal((await account.ensureSenderAccount.run({}, ctx)).allowed, true);
  assert.equal((await booking.getSenderRothBalance.run({}, ctx)).balance, 0);
  assert.equal((await db.doc("walletTransactions/sender_welcome_roth_legacy").get()).exists, false);
});
