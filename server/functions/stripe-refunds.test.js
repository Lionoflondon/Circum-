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
          if (name === "businessRothPurchases") {
            return {
              limit() {
                return {
                  async get() {
                    return {docs: [], empty: true};
                  },
                };
              },
            };
          }
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
          return {id, path: `${name}/${id}`};
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

  assert.equal(result.handled, false);
  assert.equal(result.reviewRequired, true);
  assert.equal(result.reason, "multiple_deliveries_for_payment_intent");
  assert.deepEqual(result.deliveryIds, ["delivery-a", "delivery-b"]);
  assert.equal(writes.length, 2);
  assert.equal(writes[0].data.reviewRequired, true);
  assert.equal(writes[1].data.actionType, "stripe_refund_requires_review");
});
