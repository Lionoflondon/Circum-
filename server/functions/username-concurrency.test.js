"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {initializeApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {_claimUsernameForUid: claim} = require("./username-authority");

test("concurrent claims have one owner and no split profile state", async () => {
  const app = initializeApp({projectId: "circum-username-concurrency-test"}, `username-${Date.now()}`);
  const db = getFirestore(app);
  await Promise.all([
    db.collection("users").doc("uid-a").set({displayName: "A"}),
    db.collection("users").doc("uid-b").set({displayName: "B"}),
  ]);
  const results = await Promise.allSettled([
    claim({db, uid: "uid-a", normalized: "jason", display: "jason"}),
    claim({db, uid: "uid-b", normalized: "jason", display: "jason"}),
  ]);
  assert.equal(results.filter((result) => result.status === "fulfilled").length, 1);
  assert.equal(results.filter((result) => result.status === "rejected").length, 1);
  const registry = await db.collection("usernames").doc("jason").get();
  assert.equal(registry.data().status, "active");
  const owner = registry.data().uid;
  const [ownerProfile, otherProfile] = await Promise.all([
    db.collection("users").doc(owner).get(),
    db.collection("users").doc(owner === "uid-a" ? "uid-b" : "uid-a").get(),
  ]);
  assert.equal(ownerProfile.data().username, "jason");
  assert.equal(otherProfile.data().username, undefined);
});
