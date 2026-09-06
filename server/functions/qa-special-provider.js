/* eslint-disable max-len, require-jsdoc */
"use strict";
const {createHash} = require("node:crypto");
const ROUTING_TYPE = "qa_isolated_special_flow";
const hash = (value) => createHash("sha256").update(value).digest("hex");
function reject(message) {
 throw new Error(`QA provider: ${message}`);
}
function providerForFixture({stripe, registry, fixtureId, secret, now = Date.now}) {
  if (!secret || !secret.startsWith("sk_test_") || !/^[a-f0-9]{64}$/.test(fixtureId)) reject("TEST configuration required");
  const assertObject = (object) => {
    if (!object || object.livemode !== false || object.currency !== "gbp" || !object.metadata || object.metadata.qaFixtureId !== fixtureId || object.metadata.type !== ROUTING_TYPE) reject("foreign provider object");
    return object;
  };
  async function realize(record) {
    // Never retry creation after Stripe's minimum idempotency retention window.
    if (now() - record.createdAt >= 23 * 3600000) reject("creation requires manual provider reconciliation; do not recreate");
    const object = assertObject(await stripe.checkout.sessions.create(record.params, {idempotencyKey: record.key}));
    if (object.amount_total !== record.amount) reject("provider amount mismatch");
    await registry.doc(record.id).set({providerId: object.id}, {merge: true});
    return object;
  }
  async function create(params, options) {
    if (!options || !options.idempotencyKey || params.mode !== "payment" || params.discounts || params.subscription_data) reject("only one-off idempotent checkout is permitted");
    if (!params.metadata || !["health_plus_payment", "business_invoice_payment"].includes(params.metadata.type)) reject("unsupported canonical flow");
    const amount = (params.line_items || []).reduce((sum, item) => {
      const p = item.price_data;
      if (!p || p.currency !== "gbp" || !Number.isSafeInteger(p.unit_amount) || p.unit_amount <= 0 || !Number.isSafeInteger(item.quantity) || item.quantity < 1) reject("invalid minor units");
      return sum + p.unit_amount * item.quantity;
    }, 0);
    if (!Number.isSafeInteger(amount) || amount <= 0 || amount > 10000) reject("amount outside QA cap");
    const id = hash(options.idempotencyKey);
    const key = `qa_special_${fixtureId}_${id}`;
    // Strip all routing metadata, including Health+'s feature fallback. No public
    // webhook can finalize this private fixture through a production collection.
    const metadata = {type: ROUTING_TYPE, qaFixtureId: fixtureId, canonicalType: params.metadata.type};
    const safe = {...params, metadata, payment_intent_data: {metadata}, success_url: "https://example.invalid/qa", cancel_url: "https://example.invalid/qa"};
    delete safe.customer; delete safe.customer_email; delete safe.client_reference_id;
    const candidate = {id, key, amount, params: safe, createdAt: now(), binding: hash(JSON.stringify(safe))};
    try {
 await registry.doc(id).create(candidate);
} catch (error) {
 if (error.code !== 6 && error.code !== "already-exists") throw error;
}
    const record = (await registry.doc(id).get()).data();
    if (record.binding !== candidate.binding) reject("request changed under the same identity");
    if (record.providerId) return assertObject(await stripe.checkout.sessions.retrieve(record.providerId));
    return realize(record);
  }
  async function retrieve(id) {
    const object = assertObject(await stripe.checkout.sessions.retrieve(id));
    const records = await registry.where("providerId", "==", id).get();
    if (records.empty || records.size !== 1 || object.amount_total !== records.docs[0].data().amount) reject("unregistered provider identity");
    return object;
  }
  async function expire(id) {
    const current = await retrieve(id);
    if (current.payment_status === "paid" || current.status === "complete") reject("unexpected capture requires reconciliation");
    if (current.status === "expired") return current;
    const expired = assertObject(await stripe.checkout.sessions.expire(id));
    if (expired.status !== "expired" || expired.payment_status === "paid") reject("expiry unconfirmed");
    return expired;
  }
  async function cleanup() {
    const all = await registry.get();
    for (const snap of all.docs) {
      const record = snap.data();
      const object = record.providerId ? await retrieve(record.providerId) : await realize(record);
      await expire(object.id);
      await snap.ref.set({terminalStatus: "expired", cleanedAt: now()}, {merge: true});
    }
    return {expired: all.size};
  }
  return {checkout: {sessions: {create, retrieve, expire}}, cleanup};
}
module.exports = {providerForFixture, ROUTING_TYPE};
