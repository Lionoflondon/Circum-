"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {createCalculateEarningsHandler, createRetrieveCardDetailsHandler} =
  require("./legacy-financial-endpoints")._test;

function snapshot(data) {
  return {exists: data !== undefined, data: () => data};
}

function database(records = {}, histories = {}) {
  return {
    collection(name) {
      return {
        doc(id) {
          return {get: async () => snapshot(records[`${name}/${id}`])};
        },
        where(_field, _operator, value) {
          const rows = histories[`${name}/${value}`] || [];
          const query = {
            where() {
              return query;
            },
            async get() {
              return {
                size: rows.length,
                forEach(callback) {
                  rows.forEach((row) => callback({data: () => row}));
                },
              };
            },
          };
          return query;
        },
      };
    },
  };
}

function auth(tokens = {}) {
  return {
    async verifyIdToken(token) {
      if (!tokens[token]) throw new Error("invalid token");
      return tokens[token];
    },
  };
}

function request(token, body = {}) {
  return {
    method: "POST",
    headers: token ? {authorization: `Bearer ${token}`} : {},
    body,
  };
}

function response() {
  return {
    headers: {},
    statusCode: 200,
    payload: null,
    set(name, value) {
      this.headers[name] = value;
      return this;
    },
    status(value) {
      this.statusCode = value;
      return this;
    },
    json(value) {
      this.payload = value;
      return this;
    },
    send(value) {
      this.payload = value;
      return this;
    },
  };
}

test("RetrieveCardDetails rejects unauthenticated and wrong-owner requests", async () => {
  let stripeCalls = 0;
  const handler = createRetrieveCardDetailsHandler({
    auth: auth({sender: {uid: "sender-a"}}),
    db: database({"users/sender-a": {stripeCustomerId: "cus_a"}}),
    stripe: {paymentMethods: {list: async () => {
      stripeCalls += 1;
      return {data: []};
    }}},
  });
  const unauthenticated = response();
  await handler(request("", {customerId: "cus_a"}), unauthenticated);
  assert.equal(unauthenticated.statusCode, 401);

  const wrongOwner = response();
  await handler(request("sender", {customerId: "cus_b"}), wrongOwner);
  assert.equal(wrongOwner.statusCode, 403);
  assert.equal(stripeCalls, 0);
});

test("RetrieveCardDetails allows only the owner or an active financial admin", async () => {
  const records = {
    "users/sender-a": {stripeCustomerId: "cus_a"},
    "adminUsers/admin-a": {status: "active", role: "support_agent"},
  };
  const handler = createRetrieveCardDetailsHandler({
    auth: auth({
      sender: {uid: "sender-a"},
      admin: {uid: "admin-a", role: "support_agent"},
    }),
    db: database(records),
    stripe: {paymentMethods: {list: async ({customer}) => ({
      data: [{id: `pm_${customer}`, type: "card", card: {brand: "visa", last4: "4242"}}],
    })}},
  });
  const owner = response();
  await handler(request("sender", {customerId: "cus_a"}), owner);
  assert.equal(owner.statusCode, 200);
  assert.equal(owner.payload.paymentMethods[0].last4, "4242");

  const admin = response();
  await handler(request("admin", {customerId: "cus_b"}), admin);
  assert.equal(admin.statusCode, 200);
});

test("calculateEarnings rejects unauthenticated and Rider cross-account requests", async () => {
  const handler = createCalculateEarningsHandler({
    auth: auth({rider: {uid: "rider-a"}}),
    db: database({"riders/rider-a": {status: "online"}, "riders/rider-b": {status: "online"}}),
  });
  const unauthenticated = response();
  await handler(request("", {riderId: "rider-a"}), unauthenticated);
  assert.equal(unauthenticated.statusCode, 401);

  const crossAccount = response();
  await handler(request("rider", {riderId: "rider-b"}), crossAccount);
  assert.equal(crossAccount.statusCode, 403);
});

test("calculateEarnings denies customers and unknown Riders", async () => {
  const handler = createCalculateEarningsHandler({
    auth: auth({customer: {uid: "customer-a"}, rider: {uid: "missing-rider"}}),
    db: database({}),
  });
  const customer = response();
  await handler(request("customer", {riderId: "customer-a"}), customer);
  assert.equal(customer.statusCode, 404);

  const unknownRider = response();
  await handler(request("rider", {riderId: "missing-rider"}), unknownRider);
  assert.equal(unknownRider.statusCode, 404);
});

test("calculateEarnings permits active financial admin operational access", async () => {
  const records = {
    "adminUsers/admin-a": {status: "active", role: "finance_admin"},
    "riders/rider-b": {status: "online"},
    "payments/rider-b": {accountBalance: 12.5},
  };
  const handler = createCalculateEarningsHandler({
    auth: auth({admin: {uid: "admin-a", role: "finance_admin"}}),
    db: database(records, {"history/rider-b": []}),
  });
  const result = response();
  await handler(request("admin", {riderId: "rider-b"}), result);
  assert.equal(result.statusCode, 200);
  assert.equal(result.payload.accountBalance, 12.5);
});

test("calculateEarnings rejects an admin without a financial operations role", async () => {
  const records = {
    "adminUsers/admin-a": {status: "active", role: "driver_manager"},
    "riders/rider-b": {status: "online"},
  };
  const handler = createCalculateEarningsHandler({
    auth: auth({admin: {uid: "admin-a", role: "driver_manager"}}),
    db: database(records),
  });
  const result = response();
  await handler(request("admin", {riderId: "rider-b"}), result);
  assert.equal(result.statusCode, 403);
});
