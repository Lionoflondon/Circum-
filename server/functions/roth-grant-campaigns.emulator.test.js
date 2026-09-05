"use strict";

const settleConcurrent = require("./test-helpers/settle-concurrent");

const assert = require("assert");
const {test, before, after} = require("node:test");
const {initializeApp, getApps, deleteApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {BALANCE_TYPES, TRANSACTION_TYPES} = require("./roth-ledger-core");
const {recordRothMovement} = require("./roth-ledger");

const projectId = "circum-roth-grant-emulator";
const emulatorAvailable = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
let app;
let db;

before(() => {
  if (!emulatorAvailable) return;
  app = getApps()[0] || initializeApp({projectId});
  db = getFirestore(app);
});

after(async () => {
  if (app) await deleteApp(app);
});

test("campaign grant is atomic and duplicate/concurrent settlement is one economic event", {skip: !emulatorAvailable}, async () => {
  const uid = "campaign-user-1";
  const campaignId = "campaign-emulator-1";
  const key = `roth_campaign:${campaignId}:${uid}`;
  const args = {
    db,
    userId: uid,
    uid,
    amount: 10,
    balanceType: BALANCE_TYPES.rothCredit,
    type: TRANSACTION_TYPES.adminCredit,
    reason: "Emulator campaign grant",
    issuedByAdminId: "finance-admin",
    transactionId: `roth_campaign_${campaignId}_${uid}`,
    idempotencyKey: key,
    relatedEntityId: campaignId,
    metadata: {source: "roth_grant_campaign", sourceType: "roth_grant_campaign", campaignId},
  };
  await settleConcurrent([recordRothMovement(args), recordRothMovement(args), recordRothMovement(args)]);
  const wallet = await db.collection("wallets").doc(uid).get();
  const ledger = await db.collection("walletTransactions").doc(args.transactionId).get();
  const idempotency = await db.collection("rothMovementIdempotency").where("idempotencyKey", "==", args.idempotencyKey).get();
  assert.equal(wallet.data().balance, 10);
  assert.equal(ledger.data().amount, 10);
  assert.equal(ledger.data().metadata.campaignId, campaignId);
  assert.equal(idempotency.size, 1);
});

test("dry-run style recipient records do not mutate the wallet or ledger", {skip: !emulatorAvailable}, async () => {
  const campaignId = "campaign-emulator-dry-run";
  await db.collection("rothGrantCampaigns").doc(campaignId).set({status: "dry_run_complete", estimatedRecipients: 1, estimatedRothLiability: 10});
  await db.collection("rothGrantCampaigns").doc(campaignId).collection("recipients").doc("dry-user").set({grantStatus: "pending", amountRoth: 10});
  const wallet = await db.collection("wallets").doc("dry-user").get();
  const ledger = await db.collection("walletTransactions").where("uid", "==", "dry-user").get();
  assert.equal(wallet.exists, false);
  assert.equal(ledger.empty, true);
});

test("individual grant idempotency is one wallet mutation and one ledger event", {skip: !emulatorAvailable}, async () => {
  const uid = "individual-user-1";
  const grantId = "individual-emulator-1";
  const args = {
    db, userId: uid, uid, amount: 25,
    balanceType: BALANCE_TYPES.rothCredit,
    type: TRANSACTION_TYPES.adminCredit,
    reason: "Individual emulator grant",
    issuedByAdminId: "finance-admin",
    transactionId: `roth_admin_grant_${grantId}_${uid}`,
    idempotencyKey: `admin_roth_grant:${grantId}:${uid}`,
    relatedEntityId: grantId,
    metadata: {source: "admin_individual_grant", sourceType: "admin_roth_grant", grantId},
  };
  await settleConcurrent([recordRothMovement(args), recordRothMovement(args)]);
  const wallet = await db.collection("wallets").doc(uid).get();
  const ledger = await db.collection("walletTransactions").doc(args.transactionId).get();
  const idempotency = await db.collection("rothMovementIdempotency").where("idempotencyKey", "==", args.idempotencyKey).get();
  assert.equal(wallet.data().balance, 25);
  assert.equal(ledger.data().metadata.grantId, grantId);
  assert.equal(idempotency.size, 1);
});

test("high contention identical and distinct individual grants preserve every economic event", {skip: !emulatorAvailable}, async () => {
  const uid = "individual-contention-user";
  const duplicate = {
    db, userId: uid, uid, amount: 3, balanceType: BALANCE_TYPES.rothCredit,
    type: TRANSACTION_TYPES.adminCredit, reason: "Contention grant", issuedByAdminId: "finance-admin",
    transactionId: "roth_admin_grant_contention_same", idempotencyKey: "admin_roth_grant:contention:same", relatedEntityId: "contention-same",
    metadata: {source: "admin_individual_grant", grantId: "contention-same"},
  };
  await settleConcurrent(Array.from({length: 20}, () => recordRothMovement(duplicate)));
  await settleConcurrent(Array.from({length: 5}, (_, index) => recordRothMovement({
    ...duplicate, amount: 2, transactionId: `roth_admin_grant_contention_${index}`, idempotencyKey: `admin_roth_grant:contention:${index}`, relatedEntityId: `contention-${index}`,
    metadata: {source: "admin_individual_grant", grantId: `contention-${index}`},
  })));
  const wallet = await db.collection("wallets").doc(uid).get();
  const ledger = await db.collection("walletTransactions").where("uid", "==", uid).get();
  assert.equal(wallet.data().balance, 13);
  assert.equal(ledger.size, 6);
  assert.equal(ledger.docs.reduce((total, doc) => total + Number(doc.data().amount), 0), 13);
});

test("conflicting idempotency payload fails closed and campaign plus individual race has no lost update", {skip: !emulatorAvailable}, async () => {
  const uid = "individual-conflict-user";
  const base = {
    db, userId: uid, uid, amount: 7, balanceType: BALANCE_TYPES.rothCredit,
    type: TRANSACTION_TYPES.adminCredit, reason: "Conflict grant", issuedByAdminId: "finance-admin",
    transactionId: "roth_admin_grant_conflict", idempotencyKey: "admin_roth_grant:conflict:one", relatedEntityId: "conflict-one",
    metadata: {source: "admin_individual_grant", grantId: "conflict-one"},
  };
  await recordRothMovement(base);
  await assert.rejects(() => recordRothMovement({...base, amount: 8}));
  await settleConcurrent([
    recordRothMovement({...base, amount: 5, transactionId: "roth_campaign_race_campaign_race-user", idempotencyKey: "roth_campaign:race:race-user", relatedEntityId: "race", metadata: {source: "roth_grant_campaign", campaignId: "race"}}),
    recordRothMovement({...base, amount: 4, transactionId: "roth_admin_grant_race-two", idempotencyKey: "admin_roth_grant:race:two", relatedEntityId: "race-two", metadata: {source: "admin_individual_grant", grantId: "race-two"}}),
  ]);
  const wallet = await db.collection("wallets").doc(uid).get();
  const ledger = await db.collection("walletTransactions").where("uid", "==", uid).get();
  assert.equal(wallet.data().balance, 16);
  assert.equal(ledger.docs.reduce((total, doc) => total + Number(doc.data().amount), 0), 16);
});

test("ledger read abort retries as one batch before any economic write", {skip: !emulatorAvailable}, async () => {
  let reads = 0;
  const wrapped = {
    collection: db.collection.bind(db),
    runTransaction: (callback) => db.runTransaction((tx) => callback(new Proxy(tx, {
      get(target, property) {
        if (property === "get") {
return () => {
 throw new Error("Do not fan out transaction reads.");
};
}
        if (property === "getAll") {
return async (...refs) => {
          reads++;
          if (reads === 1) throw Object.assign(new Error("Injected read abort"), {code: 10});
          return target.getAll(...refs);
        };
}
        const value = target[property];
        return typeof value === "function" ? value.bind(target) : value;
      },
    }))),
  };
  await recordRothMovement({db: wrapped, userId: "batch-read-retry", uid: "batch-read-retry", amount: 2,
    balanceType: BALANCE_TYPES.rothCredit, type: TRANSACTION_TYPES.adminCredit,
    reason: "Read abort retry", transactionId: "batch-read-retry", idempotencyKey: "batch-read-retry"});
  assert.equal(reads, 2);
  assert.equal((await db.doc("wallets/batch-read-retry").get()).data().balance, 2);
  assert.equal((await db.collection("walletTransactions").where("uid", "==", "batch-read-retry").get()).size, 1);
});
