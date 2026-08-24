"use strict";

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
  await Promise.all([recordRothMovement(args), recordRothMovement(args), recordRothMovement(args)]);
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
  await Promise.all([recordRothMovement(args), recordRothMovement(args)]);
  const wallet = await db.collection("wallets").doc(uid).get();
  const ledger = await db.collection("walletTransactions").doc(args.transactionId).get();
  const idempotency = await db.collection("rothMovementIdempotency").where("idempotencyKey", "==", args.idempotencyKey).get();
  assert.equal(wallet.data().balance, 25);
  assert.equal(ledger.data().metadata.grantId, grantId);
  assert.equal(idempotency.size, 1);
});
