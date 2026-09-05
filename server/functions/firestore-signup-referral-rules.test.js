/* eslint-disable max-len, require-jsdoc */
const {test, before, after} = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {initializeTestEnvironment, assertFails, assertSucceeds} = require("@firebase/rules-unit-testing");
const {doc, getDoc, setDoc, updateDoc, deleteDoc} = require("firebase/firestore");
const referrals = require("./referrals");
let app; let db; let env;
const context = (uid) => ({auth: {uid, token: {email: `${uid}@example.invalid`}}});
const attach = (uid, code) => referrals.attachReferralCode.run({referralCode: code}, context(uid));
before(async () => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST);
  const projectId = "demo-signup-referral";
  app = initializeApp({projectId}); db = getFirestore();
  env = await initializeTestEnvironment({projectId, firestore: {rules: fs.readFileSync(path.join(__dirname, "../../firestore.rules"), "utf8")}});
  for (const uid of ["friend", "other", "new", "self", "reward", "blocked", "invalid"]) {
    await db.doc(`users/${uid}`).set({uid, email: `${uid}@example.invalid`});
    await db.doc(`referralCodes/${uid.toUpperCase()}`).set({userId: uid, userEmail: `${uid}@example.invalid`});
  }
});
after(async () => {
if (env) await env.cleanup(); if (app) await deleteApp(app);
});
test("normalized attach is transactional, idempotent, cannot overwrite and never awards at signup", async () => {
  assert.equal((await attach("new", " f r-i_end ")).status, "applied");
  const before = (await db.doc("referrals/new").get()).data();
  const results = await Promise.all([attach("new", "OTHER"), attach("new", "NEW"), attach("new", "FRIEND")]);
  assert.ok(results.every((r) => r.status === "already_attached"));
  assert.deepEqual((await db.doc("referrals/new").get()).data(), before);
  for (const field of ["referrerUserId", "inviterUserId", "referrerEmail", "referredUserId", "referredEmail", "referralCode", "status", "rewardStatus", "rewardAmount", "rewardCurrency", "rewardSource", "createdAt", "signedUpAt", "updatedAt"]) assert.ok(field in before, field);
  assert.equal(before.status, "SIGNED_UP");
  assert.equal((await db.doc("walletTransactions/referral_reward_new_referred").get()).exists, false);
});
test("expected rejection statuses and malformed/unauthenticated abuse", async () => {
  assert.equal((await attach("invalid", "??")).status, "invalid");
  assert.equal((await attach("invalid", "MISSING")).status, "not_found");
  assert.equal((await attach("self", "SELF")).status, "rejected_self_referral");
  assert.equal((await db.doc("referrals/self").get()).data().rewardAmount, 0);
  assert.equal((await attach("self", "FRIEND")).status, "applied");
  await assert.rejects(referrals.attachReferralCode.run({}, context("invalid")), {code: "invalid-argument"});
  await assert.rejects(referrals.attachReferralCode.run({referralCode: "FRIEND"}, {}), {code: "unauthenticated"});
  await assert.rejects(referrals.activateReferral.run({}, context("new")), {code: "permission-denied"});
});
async function activity(uid, fields, collection = "deliveryRequests") {
  const id = `${uid}-${collection}`;
  const after = {senderId: uid, ...fields};
  await db.doc(`${collection}/${id}`).set(after);
  const trigger = collection === "giftRequests" ? referrals.activateReferralOnGiftCompleted : collection === "prescriptionPickups" ? referrals.activateReferralOnHealthPlusCompleted : referrals.activateReferralOnDeliveryCompleted;
  const params = collection === "giftRequests" ? {giftRequestId: id} : collection === "prescriptionPickups" ? {pickupId: id} : {deliveryId: id};
  await trigger.run({before: {data: () => ({status: "pending"})}, after: {data: () => after}}, {params});
}
test("only paid completed backend activity awards both sides exactly once", async () => {
  await attach("reward", "FRIEND");
  await activity("reward", {status: "completed", paymentStatus: "paid"});
  await activity("reward", {status: "completed", paymentStatus: "paid"});
  for (const role of ["referrer", "referred"]) {
    const snap = await db.doc(`walletTransactions/referral_reward_reward_${role}`).get();
    assert.equal(snap.exists, true); assert.equal(snap.data().amount, 5);
  }
  assert.equal((await db.doc("referrals/reward").get()).data().status, "ROTH_AWARDED");
});
test("unpaid, failed, cancelled and refunded completions never activate", async () => {
  await attach("blocked", "FRIEND");
  for (const collection of ["deliveryRequests", "giftRequests", "prescriptionPickups"]) {
    for (const fields of [{status: "completed", paymentStatus: "failed"}, {status: "cancelled", paymentStatus: "paid"}, {status: "completed", paymentStatus: "paid", refundStatus: "refunded"}, {status: "completed", paymentStatus: "paid", refundStatus: "partially_refunded"}]) await activity("blocked", fields, collection);
  }
  for (const collection of ["giftRequests", "prescriptionPickups"]) await activity("blocked", {status: "delivered", paymentStatus: "paid"}, collection);
  assert.equal((await db.doc("walletTransactions/referral_reward_blocked_referred").get()).exists, false);
});
test("referrals and wallets remain private backend write authority", async () => {
  for (const uid of ["new", "friend"]) await assertSucceeds(getDoc(doc(env.authenticatedContext(uid).firestore(), "referrals/new")));
  await assertFails(getDoc(doc(env.authenticatedContext("other").firestore(), "referrals/new")));
  for (const collection of ["referrals", "wallets", "walletTransactions"]) {
    const ref = doc(env.authenticatedContext("new").firestore(), collection, "new");
    await assertFails(setDoc(ref, {referredUserId: "new", referrerUserId: "new", userId: "new", amount: 100}));
    await assertFails(updateDoc(ref, {amount: 100})); await assertFails(deleteDoc(ref));
  }
});

test("paid Gift and Health completion triggers retain reward authority", async () => {
  for (const collection of ["giftRequests", "prescriptionPickups"]) {
    const uid = `paid-${collection}`;
    await db.doc(`users/${uid}`).set({uid, email: `${uid}@example.invalid`});
    await attach(uid, "FRIEND");
    await activity(uid, {status: "completed", paymentStatus: "paid"}, collection);
    assert.equal((await db.doc(`walletTransactions/referral_reward_${uid}_referred`).get()).data().amount, 5);
  }
});

test("competing initial codes have exactly one winner and same-email self-referral is rejected", async () => {
  const uid = "race";
  await db.doc(`users/${uid}`).set({uid, email: `${uid}@example.invalid`});
  const outcomes = await Promise.all([attach(uid, "FRIEND"), attach(uid, "OTHER")]);
  assert.deepEqual(outcomes.map((r) => r.status).sort(), ["already_attached", "applied"]);
  const saved = (await db.doc(`referrals/${uid}`).get()).data();
  assert.ok(["friend", "other"].includes(saved.referrerUserId));
  await db.doc("referralCodes/SAMEEMAIL").set({userId: "different-uid", userEmail: "invalid@example.invalid"});
  assert.equal((await attach("invalid", "SAMEEMAIL")).status, "rejected_self_referral");
  assert.equal((await db.doc("walletTransactions/referral_reward_invalid_referred").get()).exists, false);
});
