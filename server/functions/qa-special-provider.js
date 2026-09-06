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

function paymentProviderForFixture({stripe, qa, fixture, secret}) {
  if (!secret || !secret.startsWith("sk_test_") || !fixture || fixture.isSyntheticQa !== true) reject("TEST payment configuration required");
  const registry = qa.collection("qaProviderObjects");
  const assertIntent = (intent) => {
    if (!intent || intent.livemode !== false || intent.currency !== "gbp" || intent.status !== "succeeded" || intent.amount_received !== intent.amount || !intent.metadata || intent.metadata.qaFixtureId !== fixture.id || intent.metadata.isSyntheticQa !== "true") reject("unverified TEST payment intent");
    return intent;
  };
  const find = async (providerId) => {
    const rows = await registry.where("providerId", "==", providerId).get();
    if (rows.size !== 1 || rows.docs[0].data().providerKind !== "payment_intent") reject("unregistered TEST payment intent");
    return rows.docs[0];
  };
  const paymentIntents = {
    create: async (input, options = {}) => {
      if (!options.idempotencyKey || !Number.isSafeInteger(input.amount) || input.amount < 1 || input.amount > 10000 || input.currency !== "gbp" || input.confirm !== true || input.payment_method !== "pm_card_visa") reject("invalid bounded TEST payment request");
      if (!input.metadata || input.metadata.qaFixtureId !== fixture.id || input.metadata.isSyntheticQa !== "true") reject("payment scope mismatch");
      const delivery = await qa.collection("deliveryRequests").doc(input.metadata.deliveryId).get();
      if (!delivery.exists || delivery.data().closing || delivery.data().status === "cancelled") reject("payment delivery unavailable");
      const id = `actual_pi_${hash(options.idempotencyKey)}`; const ref = registry.doc(id);
      const binding = hash(JSON.stringify({amount: input.amount, currency: input.currency, metadata: input.metadata}));
      try {
        await ref.create({providerKind: "payment_intent", binding, metadata: input.metadata, createdAt: Date.now()});
      } catch (error) {
        if (error.code !== 6 && error.code !== "already-exists") throw error;
      }
      const record = (await ref.get()).data();
      if (record.binding !== binding) reject("payment request changed under one identity");
      const intent = record.providerId ? await stripe.paymentIntents.retrieve(record.providerId) : await stripe.paymentIntents.create({...input, metadata: {...input.metadata, type: ROUTING_TYPE}}, {idempotencyKey: `qa_actual_${fixture.id}_${hash(options.idempotencyKey)}`});
      assertIntent(intent);
      await ref.set({providerId: intent.id, terminalStatus: null}, {merge: true});
      return intent;
    },
    retrieve: async (providerId) => {
      await find(providerId);
      return assertIntent(await stripe.paymentIntents.retrieve(providerId));
    },
  };
  const refunds = {create: async (input, options = {}) => {
    if (!options.idempotencyKey || !Number.isSafeInteger(input.amount) || input.amount < 1) reject("invalid TEST refund");
    const record = await find(input.payment_intent); const intent = assertIntent(await stripe.paymentIntents.retrieve(input.payment_intent));
    if (input.amount > intent.amount_received) reject("refund exceeds TEST payment");
    const refund = await stripe.refunds.create(input, {idempotencyKey: `qa_actual_refund_${fixture.id}_${hash(options.idempotencyKey)}`});
    if (refund.livemode !== false || refund.status !== "succeeded" || refund.payment_intent !== intent.id) reject("TEST refund unconfirmed");
    await record.ref.set({terminalStatus: "refunded", refundId: refund.id}, {merge: true});
    return refund;
  }};
  const cleanup = async () => {
    const rows = await registry.where("providerKind", "==", "payment_intent").get();
    for (const row of rows.docs) {
      const record = row.data(); if (!record.providerId || record.terminalStatus === "refunded") continue;
      const intent = assertIntent(await stripe.paymentIntents.retrieve(record.providerId));
      const prior = await stripe.refunds.list({payment_intent: intent.id, limit: 100});
      const refunded = prior.data.filter((r) => r.status === "succeeded").reduce((sum, r) => sum + r.amount, 0);
      if (refunded < intent.amount_received) await refunds.create({payment_intent: intent.id, amount: intent.amount_received - refunded, metadata: {qaFixtureId: fixture.id}}, {idempotencyKey: `cleanup_${intent.id}`});
      else await row.ref.set({terminalStatus: "refunded"}, {merge: true});
    }
    return {refunded: rows.size};
  };
  return {paymentIntents, refunds, cleanup};
}

module.exports = {providerForFixture, paymentProviderForFixture, ROUTING_TYPE};
