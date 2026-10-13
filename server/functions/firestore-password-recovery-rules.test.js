"use strict";
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {initializeTestEnvironment, assertFails} = require("@firebase/rules-unit-testing");
const {doc, getDoc, setDoc} = require("firebase/firestore");
const assert = require("node:assert/strict");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {createPasswordRecoveryHandler} = require("./password-recovery");
const projectId = `password-recovery-${process.pid}`;
let env;
let app;
test.before(async () => {
  env = await initializeTestEnvironment({projectId, firestore: {rules: fs.readFileSync(path.join(__dirname, "../../firestore.rules"), "utf8")}});
});
test.after(async () => {
  if (app) await deleteApp(app);
  if (env) await env.cleanup();
});
test("recovery requests, counters and action messages reject every direct client read and write", async () => {
  for (const context of [env.unauthenticatedContext(), env.authenticatedContext("sender"), env.authenticatedContext("rider"), env.authenticatedContext("admin", {adminRole: "super_admin"})]) {
    for (const collection of ["authPasswordResetRequests", "authPasswordResetLimits", "emailQueue"]) {
      await assertFails(getDoc(doc(context.firestore(), collection, "private")));
      await assertFails(setDoc(doc(context.firestore(), collection, "private"), {to: "attacker@example.com", recoveryMessage: "forged"}));
    }
  }
});

test("real Firestore concurrent recovery requests atomically reserve one message", async () => {
  app = initializeApp({projectId}, projectId);
  const db = getFirestore(app);
  const request = createPasswordRecoveryHandler({db, now: () => 100000});
  const results = await Promise.all(Array.from({length: 5}, () => request({email: "concurrent@example.invalid", client: "sender"}, {app: {appId: "test-app"}})));
  assert.ok(results.every((result) => result.ok === true));
  assert.equal((await db.collection("emailQueue").get()).size, 1);
  assert.equal((await db.collection("authPasswordResetRequests").get()).size, 1);
});
