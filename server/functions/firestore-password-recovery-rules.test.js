"use strict";
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {initializeTestEnvironment, assertFails} = require("@firebase/rules-unit-testing");
const {doc, getDoc, setDoc} = require("firebase/firestore");
let env;
test.before(async () => {
  env = await initializeTestEnvironment({projectId: `password-recovery-${process.pid}`, firestore: {rules: fs.readFileSync(path.join(__dirname, "../../firestore.rules"), "utf8")}});
});
test.after(async () => {
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
