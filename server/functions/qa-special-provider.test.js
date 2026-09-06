/* eslint-disable max-len, require-jsdoc */
const {test} = require("node:test");
const assert = require("node:assert/strict");
const {providerForFixture, ROUTING_TYPE} = require("./qa-special-provider");
const {routeCheckoutSessionCompleted} = require("./checkout-session-router");
function harness() {
  const records = new Map(); const objects = new Map(); let created = 0;
  const doc = (id) => ({async create(data) {
if (records.has(id)) throw Object.assign(new Error("exists"), {code: 6}); records.set(id, data);
}, async get() {
return {data: () => records.get(id)};
}, async set(data) {
records.set(id, {...records.get(id), ...data});
}});
  const snapshot = (entries) => ({size: entries.length, empty: !entries.length, docs: entries.map(([id, data]) => ({ref: doc(id), data: () => data}))});
  const registry = {doc, async get() {
return snapshot([...records]);
}, where(field, op, value) {
return {get: async () => snapshot([...records].filter(([, d]) => d[field] === value))};
}};
  const stripe = {checkout: {sessions: {
    async create(params, options) {
if (!objects.has(options.idempotencyKey)) {
created++; objects.set(options.idempotencyKey, {id: "cs_test_" + created, livemode: false, currency: "gbp", amount_total: params.line_items[0].price_data.unit_amount, status: "open", payment_status: "unpaid", metadata: params.metadata});
} return objects.get(options.idempotencyKey);
},
    async retrieve(id) {
return [...objects.values()].find((o) => o.id === id);
},
    async expire(id) {
const o = await this.retrieve(id); o.status = "expired"; return o;
},
  }}};
  const deps = {stripe, registry, fixtureId: "a".repeat(64), secret: "sk_test_fixture", now: () => 1000};
  return {qa: providerForFixture(deps), deps, records, objects, created: () => created};
}
const params = () => ({mode: "payment", metadata: {type: "health_plus_payment", feature: "health_plus", senderId: "private"}, customer_email: "private@example.invalid", line_items: [{quantity: 1, price_data: {currency: "gbp", unit_amount: 500}}]});
test("QA actual-provider adapter isolates routing and PII and is retry-stable", async () => {
  const h = harness(); const options = {idempotencyKey: "health_booking"};
  const a = await h.qa.checkout.sessions.create(params(), options); const b = await h.qa.checkout.sessions.create(params(), options);
  assert.equal(a.id, b.id); assert.equal(h.created(), 1); assert.equal(a.metadata.type, ROUTING_TYPE); assert.equal(a.metadata.feature, undefined); assert.equal(a.metadata.senderId, undefined);
  assert.equal((await routeCheckoutSessionCompleted(a, "evt", {logger: {info() {}}})).handled, false);
  assert.equal([...h.records.values()][0].params.customer_email, undefined);
  assert.deepEqual(await h.qa.cleanup(), {expired: 1}); assert.deepEqual(await h.qa.cleanup(), {expired: 1});
});
test("QA adapter rejects LIVE credentials, unsupported modes, fractional/capped amounts and foreign identities", async () => {
  const h = harness(); assert.throws(() => providerForFixture({...h.deps, secret: "sk_live_no"}), /TEST/);
  for (const mutation of [(p) => p.mode = "subscription", (p) => p.line_items[0].price_data.unit_amount = 0.5, (p) => p.line_items[0].price_data.unit_amount = 10001, (p) => p.line_items[0].price_data.currency = "usd"]) {
    const p = params(); mutation(p); await assert.rejects(h.qa.checkout.sessions.create(p, {idempotencyKey: "reject"}));
  }
  await assert.rejects(h.qa.checkout.sessions.retrieve("foreign"), /foreign/); assert.equal(h.created(), 0);
});
test("QA cleanup recovers an unpersisted provider response through the original idempotency key", async () => {
  const h = harness(); await h.qa.checkout.sessions.create(params(), {idempotencyKey: "lost"});
  for (const r of h.records.values()) delete r.providerId;
  await h.qa.cleanup(); assert.equal(h.created(), 1);
});
test("QA cleanup never silently archives a captured or foreign payment", async () => {
  const h = harness(); const o = await h.qa.checkout.sessions.create(params(), {idempotencyKey: "capture"}); o.payment_status = "paid";
  await assert.rejects(h.qa.cleanup(), /capture/); assert.equal([...h.records.values()][0].terminalStatus, undefined);
  o.livemode = true; await assert.rejects(h.qa.cleanup(), /foreign/);
});
test("QA retry rejects changed amount and cannot recreate beyond provider retention", async () => {
  const h = harness(); await h.qa.checkout.sessions.create(params(), {idempotencyKey: "same"});
  const changed = params(); changed.line_items[0].price_data.unit_amount++;
  await assert.rejects(h.qa.checkout.sessions.create(changed, {idempotencyKey: "same"}), /changed/);
  for (const r of h.records.values()) delete r.providerId;
  await assert.rejects(providerForFixture({...h.deps, now: () => 24 * 3600000}).cleanup(), /do not recreate/);
});
