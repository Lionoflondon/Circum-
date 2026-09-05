"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const refunds = require("./scheduled-road-charge-refunds");

const charge = {
  chargeId: "congestion_charge",
  type: "daily_zone_charge",
  customerContributionPence: 900,
};
const evidence = {authoritative: true, incurred: false};

test("unused scheduled road charge defaults to one Roth entitlement", () => {
  const entitlement = refunds.createEntitlement({
    deliveryId: "d1",
    quoteId: "q1",
    charge,
    actualEvidence: evidence,
  });
  const settled = refunds.reserveRoth(entitlement, evidence);
  assert.equal(settled.state, refunds.STATES.rothSettled);
  assert.equal(settled.rothCreditedPence, 900);
  assert.equal(settled.cashRefundedPence, 0);
  assert.equal(refunds.invariant(settled), true);
});

test("unresolved actual incurrence never creates an automatic refund", () => {
  const entitlement = refunds.createEntitlement({
    deliveryId: "d2",
    quoteId: "q2",
    charge,
  });
  const result = refunds.reserveRoth(entitlement, {});
  assert.equal(result.state, refunds.STATES.pending);
  assert.equal(result.decision.reason, "actual_incurrence_unresolved");
});

test("cash requires support authority and cannot double-settle Roth", () => {
  const pending = refunds.createEntitlement({
    deliveryId: "d3",
    quoteId: "q3",
    charge,
    actualEvidence: evidence,
  });
  assert.equal(
    refunds.reserveCash(pending).decision.reason,
    "support_authorization_required",
  );
  const roth = refunds.reserveRoth(pending, evidence);
  assert.equal(
    refunds.reserveCash(roth, {supportAuthorized: true}).decision.reason,
    "roth_reversal_required",
  );
  const cash = refunds.settleCash(
    refunds.reserveCash(pending, {supportAuthorized: true}),
  );
  assert.equal(cash.state, refunds.STATES.cashSettled);
  assert.equal(refunds.invariant(cash), true);
});

test("incurred liability produces no refund entitlement settlement", () => {
  const entitlement = refunds.createEntitlement({
    deliveryId: "d4",
    quoteId: "q4",
    charge,
    actualEvidence: {authoritative: true, incurred: true},
  });
  const result = refunds.reserveRoth(entitlement, {
    authoritative: true,
    incurred: true,
  });
  assert.equal(result.decision.reason, "liability_incurred");
  assert.equal(result.rothCreditedPence, 0);
});

test("Roth settlement is deterministic and idempotent", async () => {
  const store = new Map();
  const ref = (collection, id) => ({collection, id});
  const db = {
    collection(collection) {
      return {
        doc(id) {
          const base = ref(collection, id);
          return {...base, collection, id};
        },
      };
    },
    async runTransaction(work) {
      const tx = {
        async get(target) {
          return {
            exists: store.has(`${target.collection}/${target.id}`),
            data: () => store.get(`${target.collection}/${target.id}`),
          };
        },
        set(target, value, options = {}) {
          const key = `${target.collection}/${target.id}`;
          store.set(
            key,
            options.merge ? {...(store.get(key) || {}), ...value} : value,
          );
        },
        create(target, value) {
          store.set(`${target.collection}/${target.id}`, value);
        },
        update(target, value) {
          store.set(`${target.collection}/${target.id}`, {
            ...(store.get(`${target.collection}/${target.id}`) || {}),
            ...value,
          });
        },
      };
      return work(tx);
    },
  };
  const entitlement = refunds.createEntitlement({
    deliveryId: "d5",
    quoteId: "q5",
    charge,
    actualEvidence: evidence,
  });
  entitlement.refundOwnerId = "sender-1";
  entitlement.refundablePence = 250;
  entitlement.entitlementPence = 400;
  store.set(
    `roadChargeRefundEntitlements/${entitlement.entitlementId}`,
    entitlement,
  );
  const first = await refunds.settleEntitlementToRoth({
    db,
    entitlementId: entitlement.entitlementId,
    owner: {id: "sender-1"},
  });
  const second = await refunds.settleEntitlementToRoth({
    db,
    entitlementId: entitlement.entitlementId,
    owner: {id: "sender-1"},
  });
  assert.equal(first.settled, true);
  assert.equal(first.amountPence, 250);
  assert.equal(second.duplicate, true);
  assert.equal(
    store.get(
      `walletTransactions/road_charge_refund_${entitlement.entitlementId}`,
    ).amount,
    2.5,
  );
});

test("explicit zero and partial refundable amounts are authoritative", () => {
  const zero = {
    ...refunds.createEntitlement({
      deliveryId: "d6",
      quoteId: "q6",
      charge,
      actualEvidence: evidence,
    }),
    refundablePence: 0,
  };
  assert.equal(refunds.eligibleRefund(zero, evidence).eligible, false);
  assert.equal(
    refunds.settleCash(refunds.reserveCash(zero, {supportAuthorized: true}))
      .cashRefundedPence,
    0,
  );
  const partial = {
    ...refunds.createEntitlement({
      deliveryId: "d7",
      quoteId: "q7",
      charge,
      actualEvidence: evidence,
    }),
    refundablePence: 250,
    entitlementPence: 400,
  };
  assert.equal(refunds.eligibleRefund(partial, evidence).amountPence, 250);
  assert.equal(refunds.reserveRoth(partial, evidence).rothCreditedPence, 250);
  assert.equal(refunds.invariant({...partial, rothCreditedPence: 250}), true);
});

test("legacy or malformed entitlements fail closed", () => {
  const legacy = {
    ...refunds.createEntitlement({
      deliveryId: "d8",
      quoteId: "q8",
      charge,
      actualEvidence: evidence,
    }),
  };
  delete legacy.policyVersion;
  assert.equal(
    refunds.eligibleRefund(legacy, evidence).reason,
    "unsupported_policy_version",
  );
  assert.equal(refunds.reserveRoth(legacy, evidence).rothCreditedPence, 0);
});
