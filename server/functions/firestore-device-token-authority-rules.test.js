"use strict";

const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const assert = require("node:assert/strict");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {initializeTestEnvironment, assertFails} = require("@firebase/rules-unit-testing");
const {doc, getDoc, setDoc} = require("firebase/firestore");
const authority = require("./device-token-authority");

const projectId = `device-token-authority-${process.pid}`;
let env;
let app;
let db;

test.before(async () => {
  env = await initializeTestEnvironment({projectId, firestore: {rules: fs.readFileSync(path.join(__dirname, "../../firestore.rules"), "utf8")}});
  app = initializeApp({projectId}, projectId);
  db = getFirestore(app);
});

test.after(async () => {
  if (app) await deleteApp(app);
  if (env) await env.cleanup();
});

test("notification token ownership records deny all direct client access", async () => {
  const hash = authority.tokenHash("private-device-token");
  for (const context of [env.unauthenticatedContext(), env.authenticatedContext("sender"), env.authenticatedContext("rider"), env.authenticatedContext("admin", {adminRole: "super_admin"})]) {
    await assertFails(getDoc(doc(context.firestore(), "notificationTokens", hash)));
    await assertFails(setDoc(doc(context.firestore(), "notificationTokens", hash), {uid: "attacker", active: true}));
  }
});

test("registration transfers one physical token and clears every stale profile copy", async () => {
  const token = "shared-physical-device-token";
  await Promise.all([
    db.doc("users/old-sender").set({fcmToken: token}),
    db.doc("senders/old-legacy").set({pushToken: token}),
    db.doc("riderProfiles/old-rider").set({code: token}),
  ]);
  await authority.registerProfileToken({uid: "sender-new", role: "sender", token, db});
  assert.equal(await authority.ownedProfileToken("sender-new", "sender", {db}), token);
  for (const path of ["users/old-sender", "senders/old-legacy", "riderProfiles/old-rider"]) {
    const record = (await db.doc(path).get()).data();
    assert.equal(record.fcmToken, undefined);
    assert.equal(record.pushToken, undefined);
    assert.equal(record.code, undefined);
  }
  await authority.registerProfileToken({uid: "rider-new", role: "rider", token, db});
  assert.equal(await authority.ownedProfileToken("sender-new", "sender", {db}), "");
  assert.equal(await authority.ownedProfileToken("rider-new", "rider", {db}), token);
  const record = (await db.doc(`notificationTokens/${authority.tokenHash(token)}`).get()).data();
  assert.deepEqual({uid: record.uid, role: record.role, active: record.active}, {uid: "rider-new", role: "rider", active: true});
});

test("concurrent claims settle on one canonical owner and one profile copy", async () => {
  const token = "concurrent-device-token";
  await Promise.allSettled([
    authority.registerProfileToken({uid: "sender-race", role: "sender", token, db}),
    authority.registerProfileToken({uid: "rider-race", role: "rider", token, db}),
  ]);
  const owner = (await db.doc(`notificationTokens/${authority.tokenHash(token)}`).get()).data();
  const senderToken = await authority.ownedProfileToken("sender-race", "sender", {db});
  const riderToken = await authority.ownedProfileToken("rider-race", "rider", {db});
  assert.equal([senderToken, riderToken].filter(Boolean).length, 1);
  assert.equal(owner.uid === "sender-race" ? senderToken : riderToken, token);
});
