/* eslint-disable max-len, require-jsdoc */
const {test, before, after} = require("node:test");
const fs = require("node:fs");
const {initializeTestEnvironment, assertFails, assertSucceeds} = require("@firebase/rules-unit-testing");
const {doc, getDoc, setDoc, updateDoc} = require("firebase/firestore");
let env;
before(async () => {
  env = await initializeTestEnvironment({projectId: "demo-tips-compatible-rules", firestore: {
    rules: fs.readFileSync(`${__dirname}/../../docs/releases/tips-ratings-compatible.firestore.rules`, "utf8"),
  }});
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    for (const [path, data] of [
      ["notifications/owned", {recipientId: "rider", read: false}],
      ["riderProfiles/rider", {userId: "rider", phone: "old", averageRating: 5}],
      ["publishedDriverRatings/owned", {customerId: "sender", driverId: "rider", starRating: 5, feedbackText: "Careful delivery", deliveryCategories: ["Health+"]}],
      ["deliveryTips/owned", {senderId: "sender", riderId: "rider", amountPence: 500}],
      ["riderPayoutAllocations/owned", {riderId: "rider", amountPence: 500}],
    ]) await setDoc(doc(db, path), data);
  });
});
after(async () => env && env.cleanup());
test("scoped rules preserve legacy notification state without enabling tip authority", async () => {
  const db = env.authenticatedContext("rider").firestore();
  await assertSucceeds(updateDoc(doc(db, "notifications/owned"), {read: true}));
  for (const field of ["averageRating", "ratingCount", "trustPoints", "riderRank", "approvalStatus"]) {
    await assertFails(updateDoc(doc(db, "riderProfiles/rider"), {[field]: 99}));
  }
});
test("scoped rules publish safe own feedback and deny cross-rider reads and financial writes", async () => {
  for (const uid of ["sender", "rider", "stranger"]) {
    const db = env.authenticatedContext(uid).firestore();
    if (uid === "stranger") await assertFails(getDoc(doc(db, "publishedDriverRatings/owned")));
    else await assertSucceeds(getDoc(doc(db, "publishedDriverRatings/owned")));
    for (const path of ["publishedDriverRatings/owned", "deliveryTips/owned", "riderPayoutAllocations/owned", "driverPerformanceMetrics/rider", "wallets/rider", "walletTransactions/forged", "rothMovementIdempotency/forged", "ratingPrivateFeedback/owned", "payoutRequests/forged"]) {
      await assertFails(setDoc(doc(db, path), {riderId: uid, customerId: uid, amount: 100, hiddenByAdmin: true}));
    }
  }
});
