"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const Module = require("node:module");

function fakeDatabase() {
  const records = new Map([
    ["deliveryRequests/delivery-1", {status: "completed", paymentStatus: "paid", senderId: "customer-2"}],
    ["referrals/customer-2", {status: "signed_up", referrerUserId: "inviter-1", referredUserId: "customer-2", rewardAmount: 5, referralCode: "FRIEND"}],
  ]);
  const ref = (collection, id) => ({
    id,
    path: `${collection}/${id}`,
    async get() {
      const value = records.get(this.path);
      return {exists: value !== undefined, data: () => value};
    },
    async set(value, options = {}) {
      const current = records.get(this.path) || {};
      records.set(this.path, options.merge ? {...current, ...value} : value);
    },
  });
  return {
    records,
    collection: (name) => ({doc: (id) => ref(name, id)}),
    async runTransaction(callback) {
      const tx = {
        get: (document) => document.get(),
        set: (document, value, options) => document.set(value, options),
      };
      return callback(tx);
    },
  };
}

function loadReferralsWithStubs(recordRothMovement) {
  const path = require.resolve("./referrals");
  delete require.cache[path];
  const originalLoad = Module._load;
  const fakeFunctions = {
    https: {
      HttpsError: class HttpsError extends Error { constructor(code, message) { super(message); this.code = code; } },
      onCall: (handler) => ({run: handler}),
    },
    firestore: {document: () => ({onUpdate: (handler) => ({handler})})},
  };
  Module._load = function(request, parent, isMain) {
    if (parent && parent.filename === path) {
      if (request === "firebase-functions/v1") return fakeFunctions;
      if (request === "firebase-admin/firestore") return {getFirestore: () => { throw new Error("db injection required"); }, FieldValue: {serverTimestamp: () => "timestamp", delete: () => "delete"}};
      if (request === "firebase-admin/auth") return {getAuth: () => ({getUser: async () => ({})})};
      if (request === "./roth-ledger") return {recordRothMovement};
      if (request === "./roth-ledger-core") return {BALANCE_TYPES: {rothCredit: "roth_credit"}, TRANSACTION_TYPES: {referralReward: "referral_reward", referralWelcomeReward: "referral_welcome_reward"}};
      if (request === "./referral-core") return {
        DEFAULT_REFERRAL_REWARD_ROTH: 5,
        REFERRAL_STATUSES: {signedUp: "signed_up", firstQualifyingDeliveryCompleted: "first_qualifying_delivery_completed", rothAwarded: "ROTH_AWARDED", rejected: "rejected", review: "review"},
        referralRewardFinanceMetadata: (value) => value,
      };
    }
    return originalLoad.call(this, request, parent, isMain);
  };
  try {
    return require("./referrals");
  } finally {
    Module._load = originalLoad;
    delete require.cache[path];
  }
}

test("central staging referrals never write legacy credits, including a missing-client failure", async () => {
  const previous = {
    mode: process.env.ROTH_CENTRAL_MODE,
    project: process.env.GCLOUD_PROJECT,
    configured: process.env.ROTH_COMPANY_STAGING_PROJECT,
  };
  process.env.ROTH_CENTRAL_MODE = "staging";
  process.env.GCLOUD_PROJECT = "circum-stg-71";
  process.env.ROTH_COMPANY_STAGING_PROJECT = "circum-stg-71";
  let legacyWrites = 0;
  const originalError = console.error;
  try {
    const referrals = loadReferralsWithStubs(async () => { legacyWrites += 1; });
    const db = fakeDatabase();
    console.error = () => {};
    const noClient = await referrals.handleDeliveryCompletedReferral({db, deliveryId: "delivery-1", delivery: {senderId: "customer-2"}});
    console.error = originalError;
    assert.equal(noClient.sender.status, "review");
    assert.equal(legacyWrites, 0);

    const centralCalls = [];
    const centralClient = {issueReward: async (request) => {
      centralCalls.push(request);
      return {journalId: `journal-${request.rewardId}`};
    }};
    const issued = await referrals.handleDeliveryCompletedReferral({db, deliveryId: "delivery-1", delivery: {senderId: "customer-2"}, centralClient});
    assert.equal(issued.sender.status, "ROTH_AWARDED");
    assert.equal(legacyWrites, 0);
    assert.equal(centralCalls.length, 2);
    assert.equal(db.records.get("referrals/customer-2").centralRothIssuance.amountPence, 500);
  } finally {
    console.error = originalError;
    for (const [key, value] of [["ROTH_CENTRAL_MODE", previous.mode], ["GCLOUD_PROJECT", previous.project], ["ROTH_COMPANY_STAGING_PROJECT", previous.configured]]) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  }
});
