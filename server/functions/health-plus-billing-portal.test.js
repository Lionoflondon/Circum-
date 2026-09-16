"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {createHealthPlusBillingPortalHandler} = require("./health-plus")._qaHandlers;

function response() {
  return {
    statusCode: 200,
    body: null,
    set() {},
    status(code) {
      this.statusCode = code;
      return this;
    },
    send(body) {
      this.body = body;
      return this;
    },
  };
}

function fakeDb(records) {
  return {
    collection(name) {
      return {
        doc(id) {
          return {
            async get() {
              const value = records[`${name}/${id}`];
              return {exists: value != null, data: () => value};
            },
          };
        },
      };
    },
  };
}

test("Health+ billing portal uses only the authenticated Sender customer", async () => {
  let created = null;
  const res = response();
  await createHealthPlusBillingPortalHandler({method: "POST"}, res, {
    verifySenderRequest: async () => ({uid: "sender_1", email: "sender@example.com"}),
    db: fakeDb({
      "healthPlusMemberships/sender_1": {
        senderId: "sender_1",
        stripeCustomerId: "cus_member",
      },
    }),
    stripe: {
      customers: {retrieve: async (id) => ({id, deleted: false})},
      billingPortal: {sessions: {create: async (params) => {
        created = params;
        return {url: "https://billing.stripe.com/session/test", expires_at: 123};
      }}},
    },
  });
  assert.equal(res.statusCode, 200);
  assert.equal(created.customer, "cus_member");
  assert.equal(created.return_url, "https://circum-app-2797c.web.app/?app=health");
  assert.equal(res.body.url, "https://billing.stripe.com/session/test");
});

test("Health+ billing portal fails closed when no owned customer exists", async () => {
  const res = response();
  await createHealthPlusBillingPortalHandler({method: "POST"}, res, {
    verifySenderRequest: async () => ({uid: "sender_2"}),
    db: fakeDb({}),
    stripe: {},
  });
  assert.equal(res.statusCode, 409);
  assert.equal(res.body.error, "health_plus_customer_missing");
});
