/* eslint-disable max-len */
const test = require("node:test");
const assert = require("node:assert/strict");
const {refundPatch, syncChargeRefund} = require("./stripe-refunds");

test("partial refunds remain distinct from full refunds", () => {
  const patch = refundPatch({amount: 1000, amount_refunded: 400, refunded: false, currency: "gbp", refunds: {data: [{id: "re_partial", created: 1}]}});
  assert.equal(patch.refundStatus, "partially_refunded");
  assert.equal(patch.refunded, false);
  assert.equal(patch.refundedAmount, 400);
  assert.equal(patch.stripeRefundId, "re_partial");
});

test("full refunds set loyalty-compatible fields", () => {
  const patch = refundPatch({amount: 1000, amount_refunded: 1000, refunded: true, currency: "gbp", refunds: {data: [{id: "re_full", created: 1}]}});
  assert.equal(patch.refundStatus, "refunded");
  assert.equal(patch.refunded, true);
});

test("ambiguous payment intent refund is routed to admin review", async () => {
  const writes = [];
  const db = {
    collection(name) {
      return {
        where(field, op, value) {
          assert.equal(name, "deliveryRequests");
          assert.equal(field, "stripePaymentIntentId");
          assert.equal(op, "==");
          assert.equal(value, "pi_duplicate");
          return {
            limit(size) {
              assert.equal(size, 2);
              return {
                async get() {
                  return {docs: [
                    {ref: {id: "delivery-a"}},
                    {ref: {id: "delivery-b"}},
                  ]};
                },
              };
            },
          };
        },
        doc(id = `audit-${writes.length}`) {
          return {
            id,
            path: `${name}/${id}`,
            async set(data, options) {
              writes.push({op: "set", ref: {id, path: `${name}/${id}`}, data, options});
            },
          };
        },
      };
    },
    async runTransaction(callback) {
      await callback({
        async get() {
          return {exists: false};
        },
        create(ref, data) {
          writes.push({op: "create", ref, data});
        },
        set(ref, data) {
          writes.push({op: "set", ref, data});
        },
      });
    },
  };
  const result = await syncChargeRefund({
    db,
    event: {
      id: "evt_refund",
      type: "charge.refunded",
      data: {object: {id: "ch_1", payment_intent: "pi_duplicate", amount: 1000, amount_refunded: 1000, refunded: true}},
    },
  });

  assert.equal(result.handled, true);
  assert.equal(result.actionRequired, true);
  assert.equal(result.reviewRequired, true);
  assert.equal(result.reason, "multiple_deliveries_for_payment_intent");
  assert.deepEqual(result.deliveryIds, ["delivery-a", "delivery-b"]);
  assert.equal(writes.length, 3);
  assert.equal(writes[0].data.reviewRequired, true);
  assert.equal(writes[1].data.actionType, "stripe_refund_requires_review");
  assert.equal(writes[2].data.artifactType, "refund");
  assert.equal(writes[2].data.status, "action_required");
});

test("a refund with a forged direct delivery id is captured without creating a delivery", async () => {
  const writes = [];
  const db = {
    collection(name) {
      return {
        doc(id) {
          return {
            id,
            path: `${name}/${id}`,
            async get() {
              return {exists: false};
            },
            async set(data, options) {
              writes.push({ref: {id, path: `${name}/${id}`}, data, options});
            },
          };
        },
      };
    },
    async runTransaction(callback) {
      await callback({
        async get() {
          return {exists: false};
        },
        create(ref, data) {
          writes.push({ref, data});
        },
        set(ref, data) {
          writes.push({ref, data});
        },
      });
    },
  };
  const result = await syncChargeRefund({
    db,
    event: {
      id: "evt_refund_forged_delivery",
      type: "charge.refunded",
      data: {object: {
        id: "ch_forged",
        payment_intent: "pi_forged",
        metadata: {deliveryId: "delivery_missing"},
      }},
    },
  });
  assert.equal(result.handled, false);
  assert.equal(result.actionRequired, true);
  assert.equal(result.reason, "unmatched_refund");
  assert.equal(writes.length, 1);
  assert.equal(writes[0].data.artifactType, "refund");
});

test("unmatched refund is durably captured without creating a delivery or refund mutation", async () => {
  const writes = [];
  const db = {
    collection(name) {
      if (name === "deliveryRequests") {
        return {where() {
          return {limit() {
            return {async get() {
              return {docs: []};
            }};
          }};
        }};
      }
      return {doc(id) {
        return {id, async set(data, options) {
          writes.push({name, id, data, options});
        }};
      }};
    },
  };
  const result = await syncChargeRefund({
    db,
    event: {id: "evt_unmatched_refund", type: "charge.refunded", data: {object: {id: "ch_orphan", payment_intent: "pi_orphan"}}},
  });
  assert.equal(result.handled, false);
  assert.equal(result.reason, "unmatched_refund");
  assert.equal(result.reviewRequired, true);
  assert.equal(writes.length, 1);
  assert.equal(writes[0].name, "paymentArtifactReconciliations");
  assert.equal(writes[0].data.status, "action_required");
});

function refundFixture(delivery) {
  const records = new Map([["deliveryRequests/delivery-a", {...delivery}]]);
  const db = {
    collection(name) {
      return {doc(id) {
        const path = `${name}/${id}`;
        return {id, path,
          async get() {
return {exists: records.has(path), data: () => records.get(path)};
},
          async set(data) {
records.set(path, {...records.get(path), ...data});
},
        };
      }};
    },
    async runTransaction(callback) {
      return callback({
        get: (ref) => ref.get(),
        set: (ref, data) => records.set(ref.path, {...records.get(ref.path), ...data}),
        create: (ref, data) => {
assert.equal(records.has(ref.path), false); records.set(ref.path, data);
},
      });
    },
  };
  const event = {id: "evt_refund_bound", type: "charge.refunded", data: {object: {
    id: "ch_bound", payment_intent: "pi_bound", metadata: {deliveryId: "delivery-a"},
    amount: 1000, amount_refunded: 400, currency: "gbp",
  }}};
  return {db, records, event};
}

test("existing direct delivery must match the refunded provider intent", async () => {
  for (const storedIntent of ["pi_other", undefined]) {
    const {db, records, event} = refundFixture({stripePaymentIntentId: storedIntent});
    const result = await syncChargeRefund({db, event});
    assert.equal(result.reason, "refund_payment_intent_mismatch");
    assert.equal(result.actionRequired, true);
    assert.equal(records.get("deliveryRequests/delivery-a").refundStatus, undefined);
    assert.equal(records.has("stripeWebhookEvents/evt_refund_bound"), false);
    assert.equal([...records.keys()].filter((key) => key.startsWith("paymentArtifactReconciliations/")).length, 1);
  }
});

test("matching refund is applied once and duplicate events do not rewrite it", async () => {
  const {db, records, event} = refundFixture({stripePaymentIntentId: "pi_bound"});
  assert.equal((await syncChargeRefund({db, event})).refundStatus, "partially_refunded");
  assert.equal(records.get("deliveryRequests/delivery-a").refundedAmount, 400);
  event.data.object.amount_refunded = 1000;
  assert.equal((await syncChargeRefund({db, event})).duplicate, true);
  assert.equal(records.get("deliveryRequests/delivery-a").refundedAmount, 400);
});

test("out-of-order cumulative refund cannot reduce amount or revert full refund", async () => {
  for (const prior of [{refundedAmount: 900}, {refundedAmount: 1000, refunded: true, refundStatus: "refunded"}]) {
    const {db, records, event} = refundFixture({stripePaymentIntentId: "pi_bound", ...prior});
    assert.equal((await syncChargeRefund({db, event})).stale, true);
    assert.equal(records.get("deliveryRequests/delivery-a").refundedAmount, prior.refundedAmount);
    assert.equal(records.get("deliveryRequests/delivery-a").refunded, prior.refunded);
    assert.equal(records.has("stripeWebhookEvents/evt_refund_bound"), true);
  }
});
