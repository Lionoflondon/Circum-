/* eslint-disable max-len, require-jsdoc */
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {assertFails, assertSucceeds, initializeTestEnvironment} = require("@firebase/rules-unit-testing");
const {deleteDoc, doc, setDoc, updateDoc} = require("firebase/firestore");

const rules = fs.readFileSync(path.join(__dirname, "..", "..", "firestore.rules"), "utf8");
let env;

test.before(async () => {
  env = await initializeTestEnvironment({projectId: "circum-username-rules-test", firestore: {rules}});
});
test.after(async () => env.cleanup());
test.beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "users", "owner"), {username: "oldname", displayName: "Owner"});
    await setDoc(doc(ctx.firestore(), "riders", "owner"), {handle: "oldname"});
    await setDoc(doc(ctx.firestore(), "riderProfiles", "owner"), {username: "oldname"});
    await setDoc(doc(ctx.firestore(), "usernames", "oldname"), {uid: "owner", status: "tombstoned"});
  });
});

test("direct username and handle writes are denied for Sender and Rider", async () => {
  const db = env.authenticatedContext("owner").firestore();
  await assertFails(updateDoc(doc(db, "users", "owner"), {username: "forged"}));
  await assertFails(updateDoc(doc(db, "riders", "owner"), {handle: "forged"}));
  await assertFails(updateDoc(doc(db, "riderProfiles", "owner"), {username: "forged"}));
});

test("registry and tombstone are server-only", async () => {
  const db = env.authenticatedContext("owner").firestore();
  const ref = doc(db, "usernames", "newname");
  await assertFails(setDoc(ref, {uid: "owner", status: "active"}));
  await assertFails(updateDoc(doc(db, "usernames", "oldname"), {status: "active"}));
  await assertFails(deleteDoc(doc(db, "usernames", "oldname")));
});

test("unrelated user cannot mutate another identity", async () => {
  const db = env.authenticatedContext("other").firestore();
  await assertFails(updateDoc(doc(db, "users", "owner"), {displayName: "spoof"}));
  await assertFails(updateDoc(doc(db, "riderProfiles", "owner"), {handle: "spoof"}));
});

test("canonical backend mutation is represented by server-only boundaries", () => {
  assert.match(fs.readFileSync(path.join(__dirname, "username-authority.js"), "utf8"),
      /enforceAppCheck: true/);
});
