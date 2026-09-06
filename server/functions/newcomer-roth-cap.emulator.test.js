/* eslint-disable max-len, require-jsdoc */
const {test, before, after} = require("node:test");
const assert = require("node:assert/strict");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {getAuth} = require("firebase-admin/auth");
const ledger = require("./roth-ledger");
const {BALANCE_TYPES, TRANSACTION_TYPES} = require("./roth-ledger-core");
let app; let db;
before(() => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, "Emulator required");
  app = initializeApp({projectId: "demo-newcomer-cap"}); db = getFirestore();
});
after(async () => deleteApp(app));
function referral(uid, inviter = false) {
  return ledger.recordRothMovement({db, userId: uid, uid, amount: 5,
    balanceType: BALANCE_TYPES.rothCredit,
    type: inviter ? TRANSACTION_TYPES.referralReward : TRANSACTION_TYPES.referralWelcomeReward,
    reason: inviter ? "Inviter reward" : "Joined through referral and completed first activity",
    transactionId: inviter ? `referral_reward_${uid}_referrer` : `referral_reward_${uid}_referred`,
  });
}
test("self-join and referral arrival orders award only five, preserving inviter reward", async (t) => {
  t.mock.method(getAuth(), "getUser", async (uid) => ({uid}));
  for (const order of ["starter-first", "referral-first"]) {
    const uid = order;
    if (order === "starter-first") {
      await ledger.grantSenderWelcomeRoth({uid}); await referral(uid);
    } else {
      await referral(uid); await ledger.grantSenderWelcomeRoth({uid});
    }
    await referral(uid); await ledger.grantSenderWelcomeRoth({uid});
    assert.equal((await db.doc(`wallets/${uid}`).get()).data().balance, 5);
    await referral(uid, true);
    assert.equal((await db.doc(`wallets/${uid}`).get()).data().balance, 10, "Inviting another person remains a separate earned reward");
  }
});
test("ten concurrent newcomer reward races preserve exactly five", async (t) => {
  t.mock.method(getAuth(), "getUser", async (uid) => ({uid}));
  for (let seed = 0; seed < 10; seed++) {
    const uid = `newcomer-race-${seed}`;
    await Promise.all(Array.from({length: 8}, (_, i) => i % 2 ? referral(uid) : ledger.grantSenderWelcomeRoth({uid})));
    assert.equal((await db.doc(`wallets/${uid}`).get()).data().balance, 5);
    const rows = await db.collection("walletTransactions").where("uid", "==", uid).get();
    assert.equal(rows.docs.reduce((sum, doc) => sum + doc.data().amount, 0), 5);
    assert.equal(rows.size, 1);
  }
});
test("legacy granted reward is counted without clawback and Rider referral remains five", async (t) => {
  t.mock.method(getAuth(), "getUser", async (uid) => ({uid}));
  await db.doc("walletTransactions/sender_welcome_roth_legacy").set({uid: "legacy", amount: 5});
  await db.doc("wallets/legacy").set({balance: 2, rothCredit: 2});
  await referral("legacy");
  assert.equal((await db.doc("wallets/legacy").get()).data().balance, 2, "Spent welcome reward still counts");
  await referral("rider-only"); await referral("rider-only");
  assert.equal((await db.doc("wallets/rider-only").get()).data().balance, 5);
  assert.equal((await db.doc("walletTransactions/sender_welcome_roth_rider-only").get()).exists, false);
});
