/* eslint-disable max-len */
"use strict";

const fs = require("fs");
const path = require("path");
const test = require("node:test");
const {after, before} = test;
const {assertFails, initializeTestEnvironment} = require("@firebase/rules-unit-testing");

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: "circum-ratings-tipping-rules-test",
    firestore: {rules: fs.readFileSync(path.join(__dirname, "..", "..", "firestore.rules"), "utf8")},
  });
});

after(async () => env && env.cleanup());

test("clients cannot create canonical ratings or tips", async () => {
  const sender = env.authenticatedContext("sender-a").firestore();
  await assertFails(sender.collection("driverRatings").doc("delivery-a").set({
    deliveryId: "delivery-a", senderId: "sender-a", riderId: "rider-a", starRating: 5,
  }));
  await assertFails(sender.collection("deliveryTips").doc("delivery-a").set({
    deliveryId: "delivery-a", senderId: "sender-a", riderId: "rider-a", amount: 10,
  }));
});

test("Riders cannot write earnings, tip ledger, or reversal review authority", async () => {
  const rider = env.authenticatedContext("rider-a", {role: "rider"}).firestore();
  await assertFails(rider.collection("riderEarnings").doc("rider-a").set({tipTotal: 100}, {merge: true}));
  await assertFails(rider.collection("walletTransactions").doc("delivery_tip_delivery-a").set({amount: 100}));
  await assertFails(rider.collection("riderWalletTransactions").doc("delivery_tip_delivery-a").set({amount: 100}));
  await assertFails(rider.collection("tipReconciliations").doc("delivery-a").set({status: "repaired"}));
});

test("unrelated users cannot read canonical appreciation records", async () => {
  const unrelated = env.authenticatedContext("unrelated").firestore();
  await assertFails(unrelated.collection("driverRatings").doc("delivery-a").get());
  await assertFails(unrelated.collection("deliveryTips").doc("delivery-a").get());
});
