"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {ensureStripeCustomer} = require("./sender-finance");

function fakeDb(user = {}) {
  const writes = [];
  return {
    writes,
    collection(name) {
      assert.equal(name, "users");
      return {
        doc(uid) {
          assert.equal(uid, "sender-1");
          return {
            async get() {
              return {exists: true, data: () => user};
            },
            async set(value, options) {
              writes.push({value, options});
            },
          };
        },
      };
    },
  };
}

const sender = {uid: "sender-1", email: "sender@example.com", name: "Sender"};

test("keeps an existing live Stripe customer", async () => {
  const db = fakeDb({stripeCustomerId: "cus_live"});
  const stripe = {
    customers: {
      retrieve: async (id) => ({id, deleted: false}),
      create: async () => assert.fail("must not create a replacement"),
    },
  };

  assert.equal(await ensureStripeCustomer({stripe, sender, db}), "cus_live");
  assert.equal(db.writes.length, 0);
});

test("replaces a deleted Stripe customer and repairs both stored aliases", async () => {
  const db = fakeDb({stripeCustomerId: "cus_deleted"});
  const stripe = {
    customers: {
      retrieve: async () => ({id: "cus_deleted", deleted: true}),
      create: async () => ({id: "cus_replacement"}),
    },
  };

  assert.equal(await ensureStripeCustomer({stripe, sender, db}), "cus_replacement");
  assert.equal(db.writes.length, 1);
  assert.equal(db.writes[0].value.stripeCustomerId, "cus_replacement");
  assert.equal(db.writes[0].value.customerId, "cus_replacement");
  assert.deepEqual(db.writes[0].options, {merge: true});
});

test("replaces a customer only when Stripe confirms it is missing", async () => {
  const db = fakeDb({customerId: "cus_missing"});
  const missing = new Error("missing");
  missing.code = "resource_missing";
  const stripe = {
    customers: {
      retrieve: async () => {
        throw missing;
      },
      create: async () => ({id: "cus_new"}),
    },
  };

  assert.equal(await ensureStripeCustomer({stripe, sender, db}), "cus_new");
  assert.equal(db.writes.length, 1);
});

test("does not hide unrelated Stripe failures", async () => {
  const db = fakeDb({stripeCustomerId: "cus_live"});
  const unavailable = new Error("unavailable");
  unavailable.code = "api_connection_error";
  const stripe = {
    customers: {
      retrieve: async () => {
        throw unavailable;
      },
      create: async () => assert.fail("must not create during an outage"),
    },
  };

  await assert.rejects(
      ensureStripeCustomer({stripe, sender, db}),
      /unavailable/,
  );
  assert.equal(db.writes.length, 0);
});
