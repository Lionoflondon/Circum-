/* eslint-disable max-len */
const test = require("node:test");
const fs = require("node:fs");
const path = require("node:path");
const {assertFails, assertSucceeds, initializeTestEnvironment} = require("@firebase/rules-unit-testing");
const {doc, getDoc, setDoc} = require("firebase/firestore");

let testEnv;
test.before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: "circum-referral-rules-test",
    firestore: {rules: fs.readFileSync(path.join(__dirname, "..", "..", "firestore.rules"), "utf8")},
  });
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, "referrals", "referred-1"), {referrerUserId: "referrer-1", referredUserId: "referred-1", status: "SIGNED_UP", rewardAmount: 5});
    await setDoc(doc(db, "wallets", "wallet-1"), {uid: "owner-1", userId: "owner-1", balance: 5});
    await setDoc(doc(db, "walletTransactions", "tx-1"), {uid: "owner-1", userId: "owner-1", amount: 5, type: "referral_reward"});
    await setDoc(doc(db, "users", "sender-1", "giftStories", "gift-1"), {senderId: "sender-1", storyStatus: "unlocked", storyAvailable: true});
  });
});
test.after(async () => testEnv.cleanup());

test("referral owner and referrer can read, unrelated user cannot, and clients cannot write", async () => {
  for (const uid of ["referred-1", "referrer-1"]) {
    await assertSucceeds(getDoc(doc(testEnv.authenticatedContext(uid).firestore(), "referrals", "referred-1")));
  }
  await assertFails(getDoc(doc(testEnv.authenticatedContext("other-1").firestore(), "referrals", "referred-1")));
  await assertFails(setDoc(doc(testEnv.authenticatedContext("referred-1").firestore(), "referrals", "referred-1"), {status: "ROTH_AWARDED"}, {merge: true}));
});

test("wallet owner can read wallet and ledger, unrelated user cannot, and clients cannot write", async () => {
  const owner = testEnv.authenticatedContext("owner-1").firestore();
  await assertSucceeds(getDoc(doc(owner, "wallets", "wallet-1")));
  await assertSucceeds(getDoc(doc(owner, "walletTransactions", "tx-1")));
  const other = testEnv.authenticatedContext("other-1").firestore();
  await assertFails(getDoc(doc(other, "wallets", "wallet-1")));
  await assertFails(getDoc(doc(other, "walletTransactions", "tx-1")));
  await assertFails(setDoc(doc(owner, "wallets", "wallet-1"), {balance: 500}, {merge: true}));
  await assertFails(setDoc(doc(owner, "walletTransactions", "tx-2"), {amount: 500}, {merge: true}));
});

test("Sender Gift Stories are owner-readable and backend-write only", async () => {
  const owner = testEnv.authenticatedContext("sender-1").firestore();
  await assertSucceeds(getDoc(doc(owner, "users", "sender-1", "giftStories", "gift-1")));
  const other = testEnv.authenticatedContext("other-1").firestore();
  await assertFails(getDoc(doc(other, "users", "sender-1", "giftStories", "gift-1")));
  await assertFails(setDoc(doc(owner, "users", "sender-1", "giftStories", "gift-2"), {senderId: "sender-1"}));
  await assertFails(setDoc(doc(owner, "users", "sender-1", "giftStories", "gift-1"), {storyStatus: "changed"}, {merge: true}));
});
