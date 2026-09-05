/* eslint-disable max-len, require-jsdoc */
const {test, before, after, mock} = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {getAuth} = require("firebase-admin/auth");
const {initializeTestEnvironment, assertFails, assertSucceeds} = require("@firebase/rules-unit-testing");
const {doc, getDoc, setDoc, updateDoc, deleteDoc} = require("firebase/firestore");
const referrals = require("./referrals");
const sender = require("./sender-account");
const rider = require("./rider-account");
let app; let db; let env; let code;
const ctx = (uid) => ({auth: {uid, token: {email: `${uid}@example.invalid`}}});
const attach = (uid, value = code) => referrals.attachReferralCode.run({referralCode: value, program: "rider"}, ctx(uid));
before(async () => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST);
  const projectId = "demo-rider-referral";
  app = initializeApp({projectId}); db = getFirestore(); db.settings({ignoreUndefinedProperties: true});
  mock.method(getAuth(), "getUserByEmail", async (email) => ({uid: email.split("@")[0], email}));
  env = await initializeTestEnvironment({projectId, firestore: {rules: fs.readFileSync(path.join(__dirname, "../../firestore.rules"), "utf8")}});
  await db.doc("riderProfiles/inviter").set({approvalStatus: "approved"});
  code = (await referrals.ensureRiderReferralCode.run({}, ctx("inviter"))).referralCode;
});
after(async () => {
 mock.restoreAll(); if (env) await env.cleanup(); if (app) await deleteApp(app);
});

test("only authenticated approved Riders generate stable normalized unique Rider codes", async () => {
  await assert.rejects(referrals.ensureRiderReferralCode.run({}, {}), {code: "unauthenticated"});
  await assert.rejects(referrals.ensureRiderReferralCode.run({}, ctx("no-profile")), {code: "permission-denied"});
  for (const profile of [{approvalStatus: "pending"}, {approvalStatus: "approved", isSuspended: true}]) {
    await db.doc("riderProfiles/pending").set(profile);
    await assert.rejects(referrals.ensureRiderReferralCode.run({}, ctx("pending")), {code: "permission-denied"});
    await assert.rejects(referrals.ensureReferralCode.run({}, ctx("pending")), {code: "permission-denied"});
  }
  const again = await referrals.ensureRiderReferralCode.run({}, ctx("inviter"));
  assert.equal(again.referralCode, code); assert.match(code, /^[A-Z0-9]{24}$/);
  assert.equal(again.referralLink, `https://circumuk.com/rider?referral=${code}`);
  assert.equal(again.rewardCurrency, "ROTH"); assert.equal(again.rewardAmount, 5);
  await db.doc("riderProfiles/inviter2").set({approvalStatus: "approved"});
  assert.notEqual((await referrals.ensureRiderReferralCode.run({}, ctx("inviter2"))).referralCode, code);
});

test("Rider setup starts at zero; referral attach is non-rewarding and cannot be overwritten", async () => {
  await rider.updateRiderProfile.run({fullName: "New Rider", approvalStatus: "approved", verificationStatus: "approved", dispatchEligible: true, riderRank: "legend", trustPoints: 9999}, ctx("new"));
  await rider.ensureRiderRothWallet.run({}, ctx("new"));
  assert.equal((await db.doc("riderRothWallets/new").get()).data().balance, 0);
  const profile = (await db.doc("riderProfiles/new").get()).data();
  assert.notEqual(profile.approvalStatus, "approved"); assert.notEqual(profile.verificationStatus, "approved");
  assert.notEqual(profile.dispatchEligible, true); assert.notEqual(profile.riderRank, "legend"); assert.notEqual(profile.trustPoints, 9999);
  assert.equal((await db.doc("walletTransactions/sender_welcome_roth_new").get()).exists, false);
  assert.equal((await attach("new", ` ${code.toLowerCase()} `)).status, "applied");
  const original = (await db.doc("referrals/new").get()).data();
  assert.equal(original.program, "rider"); assert.equal(original.rewardCurrency, "ROTH");
  for (const next of [code, "MISSING", "OTHER"]) assert.equal((await attach("new", next)).status, "already_attached");
  assert.deepEqual((await db.doc("referrals/new").get()).data(), original);
  assert.equal((await db.doc("walletTransactions/referral_reward_new_referred").get()).exists, false);
  assert.equal((await attach("inviter")).status, "rejected_self_referral");
  assert.equal((await db.doc("referrals/inviter").get()).data().rewardAmount, 0);
  await assert.rejects(referrals.activateReferral.run({}, ctx("new")), {code: "permission-denied"});
});

async function complete(uid, fields = {}) {
  const id = `delivery-${uid}`;
  const data = {senderId: "customer", riderId: uid, status: "completed", paymentStatus: "paid", ...fields};
  await db.doc(`deliveryRequests/${id}`).set(data);
  await referrals.activateReferralOnDeliveryCompleted.run({before: {data: () => ({status: "pending"})}, after: {data: () => data}}, {params: {deliveryId: id}});
}

test("Rider referral requires approval and paid assigned completion; concurrent repeats award exactly once", async () => {
  await complete("new");
  assert.equal((await db.doc("walletTransactions/referral_reward_new_referred").get()).exists, false);
  await db.doc("riderProfiles/new").set({approvalStatus: "approved"}, {merge: true});
  await db.doc("riders/new").set({approvalStatus: "approved", riderStatus: "approved"}, {merge: true});
  for (const fields of [{paymentStatus: "pending"}, {paymentStatus: "failed"}, {status: "failed"}, {status: "cancelled"}, {refundStatus: "refunded"}, {refundStatus: "partially_refunded"}, {riderId: "other", assignedRiderId: "new"}]) {
    await complete("new", fields);
    assert.equal((await db.doc("walletTransactions/referral_reward_new_referred").get()).exists, false);
  }
  await Promise.all([complete("new"), complete("new")]);
  await complete("new");
  for (const side of ["referrer", "referred"]) {
    const tx = (await db.doc(`walletTransactions/referral_reward_new_${side}`).get()).data();
    assert.equal(tx.amount, 5); assert.equal(tx.metadata.rewardCurrency, "ROTH");
  }
  const record = (await db.doc("referrals/new").get()).data();
  assert.equal(record.rewardAmount, 5); assert.equal(record.status, "ROTH_AWARDED");
  assert.equal(record.rewardCurrency, "ROTH"); assert.equal(record.rewardSource, "Referral");
});

test("Rider-program referral cannot unlock through the Sender completion path", async () => {
  await db.doc("riderProfiles/dual").set({approvalStatus: "approved"}); await attach("dual");
  await complete("someone-else", {senderId: "dual"});
  assert.equal((await db.doc("walletTransactions/referral_reward_dual_referred").get()).exists, false);
});

test("cross-surface bootstrap fails before profile or starter-credit mutation", async () => {
  await assert.rejects(sender.updateSenderProfile.run({firstName: "Wrong"}, ctx("new")), {code: "permission-denied"});
  assert.equal((await db.doc("users/new").get()).data()?.accountType, undefined);
  assert.equal((await db.doc("walletTransactions/sender_welcome_roth_new").get()).exists, false);
  for (const uid of ["sender-only", "admin-only"]) {
    await db.doc(`${uid === "admin-only" ? "adminUsers" : "users"}/${uid}`).set(uid === "admin-only" ? {role: "admin"} : {roles: ["sender"]});
    for (const name of ["updateRiderProfile", "advanceRiderOnboarding", "ensureRiderRothWallet", "submitRiderApplication"]) {
      await assert.rejects(rider[name].run({stage: "profile_started"}, ctx(uid)), {code: "permission-denied"});
    }
    assert.equal((await db.doc(`riderProfiles/${uid}`).get()).exists, false);
    assert.equal((await db.doc(`riderRothWallets/${uid}`).get()).exists, false);
  }
  const user = ctx("new-sender");
  await sender.ensureSenderAccount.run({}, user);
  for (let i = 0; i < 3; i++) {
 await sender.updateSenderProfile.run({firstName: "Sender"}, user); await sender.ensureSenderAccount.run({}, user);
}
  assert.equal((await db.doc("walletTransactions/sender_welcome_roth_new-sender").get()).data().amount, 5);
  assert.equal((await db.doc("users/new-sender").get()).data().starterRothGrantStatus, "granted");
});

test("client reads are private and referral, wallet and Rider authority writes fail", async () => {
  for (const uid of ["new", "inviter"]) await assertSucceeds(getDoc(doc(env.authenticatedContext(uid).firestore(), "referrals/new")));
  await assertFails(getDoc(doc(env.authenticatedContext("unrelated").firestore(), "referrals/new")));
  await assertSucceeds(getDoc(doc(env.authenticatedContext("new").firestore(), "riderRothWallets/new")));
  await assertFails(getDoc(doc(env.authenticatedContext("unrelated").firestore(), "riderRothWallets/new")));
  for (const collection of ["referrals", "wallets", "walletTransactions", "senderWallets", "riderRothWallets"]) {
    const ref = doc(env.authenticatedContext("new").firestore(), collection, "new");
    await assertFails(setDoc(ref, {userId: "new", balance: 999, amount: 999}));
    await assertFails(updateDoc(ref, {balance: 999})); await assertFails(deleteDoc(ref));
  }
  for (const collection of ["riders", "riderProfiles"]) {
    for (const field of ["approvalStatus", "verificationStatus", "dispatchEligible", "riderRank", "trustPoints"]) {
      await assertFails(updateDoc(doc(env.authenticatedContext("new").firestore(), collection, "new"), {[field]: field === "dispatchEligible" ? true : "forged-authority"}));
    }
  }
});
