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
        async getAll(...targets) {
          return Promise.all(targets.map((target) => this.get(target)));
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

for (const ownerType of ["sender", "business"]) {
  test(`${ownerType} refund read abort leaves no reads outside its callback`, async () => {
    const pending = new Set();
    let pendingAtExit = -1;
    let batchReads = 0;
    const failure = Object.assign(new Error("injected read abort"), {code: 10});
    const ref = (path) => ({
      path, id: path.split("/").pop(),
      collection: (name) => ({doc: (id) => ref(`${path}/${name}/${id}`)}),
    });
    const entitlement = {
      state: refunds.STATES.eligible,
      policyVersion: refunds.REFUND_POLICY_VERSION,
      deliveryId: "delivery", quoteId: "quote", chargeId: "charge",
      refundablePence: 250, entitlementPence: 250,
      refundOwnerType: ownerType, refundOwnerId: "owner",
    };
    const db = {
      collection: (name) => ({doc: (id) => ref(`${name}/${id}`)}),
      async runTransaction(callback) {
        let individualReads = 0;
        try {
          return await callback({
            get(target) {
              if (target.path.startsWith("roadChargeRefundEntitlements/")) {
                return Promise.resolve({exists: true, data: () => entitlement});
              }
              individualReads += 1;
              if (individualReads === 1) return Promise.reject(failure);
              return new Promise((resolve) => pending.add(resolve));
            },
            async getAll(...refs) {
              batchReads += 1;
              assert.equal(refs.length, ownerType === "sender" ? 3 : 2);
              throw failure;
            },
          });
        } finally {
          pendingAtExit = pending.size;
          // Drain injected reads after measuring callback exit, even on failure.
          for (const resolve of pending) resolve({exists: false});
          pending.clear();
        }
      },
    };
    await assert.rejects(refunds.settleEntitlementToRoth({
      db, entitlementId: "abort-probe", owner: {type: ownerType, id: "owner"},
    }), (error) => error === failure);
    assert.equal(pendingAtExit, 0, "rollback must not outlive sibling reads");
    assert.equal(batchReads, 1);
  });
}

test("cash settlement preserves support binding and retry idempotency", async () => {
  const records = new Map([
    ["roadChargeRefundEntitlements/cash-retry", {
      state: refunds.STATES.eligible,
      policyVersion: refunds.REFUND_POLICY_VERSION,
      deliveryId: "delivery", quoteId: "quote", chargeId: "charge",
      refundablePence: 900, entitlementPence: 900,
    }],
    ["supportTickets/case-1", {deliveryId: "another-delivery"}],
  ]);
  let writes = 0;
  let cashRecords = 0;
  const snapshot = (ref) => ({
    exists: records.has(ref.path), data: () => records.get(ref.path),
  });
  const db = {
    collection: (name) => ({doc: (id) => ({path: `${name}/${id}`, id})}),
    async runTransaction(callback) {
      return callback({
        async get(ref) {
          return snapshot(ref);
        },
        async getAll(...refs) {
          return refs.map(snapshot);
        },
        create(ref, data) {
          assert.equal(records.has(ref.path), false);
          records.set(ref.path, data);
          writes += 1;
          cashRecords += 1;
        },
        update(ref, data) {
          records.set(ref.path, {...records.get(ref.path), ...data});
          writes += 1;
        },
      });
    },
  };
  const args = {
    db, entitlementId: "cash-retry", actor: {authorized: true, uid: "support"},
    customerRequestReference: "case-1", cashRefundReference: "refund-1",
  };
  const denied = await refunds.settleEntitlementToCash(args);
  assert.equal(denied.reason, "support_request_delivery_mismatch");
  assert.equal(writes, 0);
  records.set("supportTickets/case-1", {deliveryId: "delivery"});
  const first = await refunds.settleEntitlementToCash(args);
  assert.equal(first.settled, true);
  assert.equal(first.amountPence, 900);
  const retry = await refunds.settleEntitlementToCash(args);
  assert.equal(retry.duplicate, true);
  assert.equal(cashRecords, 1);
  assert.equal(writes, 2);
});
