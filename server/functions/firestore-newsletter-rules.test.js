"use strict";
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {initializeTestEnvironment, assertFails} = require("@firebase/rules-unit-testing");
const {doc, getDoc, setDoc, updateDoc} = require("firebase/firestore");

const projectId = `newsletter-rules-${process.pid}`;
let env;

test.before(async () => {
  env = await initializeTestEnvironment({projectId, firestore: {rules: fs.readFileSync(path.join(__dirname, "../../firestore.rules"), "utf8")}});
  await env.withSecurityRulesDisabled(async (context) => setDoc(doc(context.firestore(), "newsletterSubscribers/hash"), {email: "private@example.com", status: "active"}));
});
test.after(async () => env.cleanup());

test("newsletter, suppression, rate-limit and analytics collections deny direct client access", async () => {
  for (const context of [env.unauthenticatedContext(), env.authenticatedContext("sender"), env.authenticatedContext("admin", {adminRole: "super_admin"})]) {
    const db = context.firestore();
    await assertFails(getDoc(doc(db, "newsletterSubscribers/hash")));
    await assertFails(setDoc(doc(db, "newsletterSubscribers/new"), {email: "x@example.com"}));
    await assertFails(updateDoc(doc(db, "newsletterSubscribers/hash"), {status: "active"}));
    await assertFails(setDoc(doc(db, "newsletterSignupRateLimits/hash"), {attempts: 0}));
    await assertFails(setDoc(doc(db, "newsletterAnalyticsEvents/event"), {event: "newsletter_signup_completed"}));
  }
});
