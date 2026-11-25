"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {createPayment, finalizePayment, handlePaymentIntent} = require("./delivery-adjustment-checkout");
function fixture() {
  const rows = new Map([["deliveryAdjustments/adj", {senderId: "sender", bookingId: "booking", riderId: "rider", status: "awaiting_sender_payment", adminDecision: "approve", additionalAmount: 1, revisedQuote: 9}], ["deliveryRequests/booking", {status: "awaiting_sender_adjustment", preAdjustmentStatus: "accepted"}]]);
  let writes = 0; let creations = 0;
  const reference = (path) => ({path, get: async () => snapshot(path), update: async (patch) => {
rows.set(path, {...rows.get(path), ...patch}); writes++;
}});
  const snapshot = (path) => ({exists: rows.has(path), id: path.split("/").pop(), data: () => ({...rows.get(path)})});
  const db = {collection: (name) => ({doc: (id) => reference(`${name}/${id}`)}), runTransaction: async (fn) => fn({get: (ref) => ref.get(), update: (ref, patch) => ref.update(patch)})};
  const session = {id: "cs_test", status: "open", payment_status: "unpaid", currency: "gbp", amount_total: 100, url: "https://checkout.stripe.com/c/pay/cs_test"};
  const intent = {id: "pi_test", client_secret: "pi_test_secret_synthetic", amount: 100, amount_received: 100, currency: "gbp", status: "succeeded"};
  const stripe = {checkout: {sessions: {create: async (params, opts) => {
creations++; session.metadata = params.metadata; intent.metadata = params.payment_intent_data.metadata; assert.equal(params.line_items[0].price_data.unit_amount, 100); assert.equal(opts.idempotencyKey, "delivery-adjustment-checkout-adj"); return {...session};
}, retrieve: async (_id, opts) => ({...session, payment_intent: opts?.expand ? intent : intent.id})}}, paymentIntents: {create: async (params) => {
creations++; intent.metadata = params.metadata; return intent;
}, retrieve: async () => intent}};
  return {rows, db, stripe, session, intent, writes: () => writes, creations: () => creations, args: {db, stripe, adjustmentId: "adj", senderId: "sender"}};
}
test("hosted checkout resumes one session and settles/replays once", async () => {
  const f = fixture();
  const first = await createPayment({...f.args, hosted: true});
  const second = await createPayment({...f.args, hosted: true});
  assert.equal(first.sessionId, second.sessionId); assert.equal(f.creations(), 1);
  f.session.status = "complete"; f.session.payment_status = "paid";
  assert.equal((await finalizePayment(f.args)).duplicate, false);
  const writes = f.writes(); assert.equal((await finalizePayment(f.args)).duplicate, true); assert.equal(f.writes(), writes);
  assert.equal(f.rows.get("deliveryRequests/booking").status, "accepted");
});
test("native payment resumes its intent and refuses a second hosted rail", async () => {
  const f = fixture(); await createPayment(f.args); await createPayment(f.args);
  assert.equal(f.creations(), 1);
  await assert.rejects(createPayment({...f.args, hosted: true}), /original platform/);
});
test("hosted reservation prevents a native double charge", async () => {
  const f = fixture(); await createPayment({...f.args, hosted: true});
  await assert.rejects(createPayment(f.args), /original platform/); assert.equal(f.creations(), 1);
});
test("ownership, invalid quote, and unapproved state fail before Stripe", async () => {
  for (const patch of [{senderId: "other"}, {additionalAmount: NaN}, {adminDecision: "reject"}]) {
    const f = fixture(); Object.assign(f.rows.get("deliveryAdjustments/adj"), patch);
    await assert.rejects(createPayment({...f.args, hosted: true})); assert.equal(f.creations(), 0);
  }
});
test("unpaid, wrong amount, owner, or session cannot settle", async () => {
  for (const mutate of [(f) => {
f.session.payment_status = "unpaid";
}, (f) => {
f.intent.amount_received = 99;
}, (f) => {
f.intent.metadata.senderId = "other";
}, (f) => {
f.session.id = "cs_unbound";
}]) {
    const f = fixture(); await createPayment({...f.args, hosted: true});
    f.session.status = "complete"; f.session.payment_status = "paid"; mutate(f);
    await assert.rejects(finalizePayment(f.args)); assert.equal(f.rows.get("deliveryRequests/booking").status, "awaiting_sender_adjustment");
  }
});
test("signed-event path validates bound intent and settles without client return", async () => {
  const f = fixture(); await createPayment({...f.args, hosted: true}); f.session.status = "complete"; f.session.payment_status = "paid";
  assert.deepEqual(await handlePaymentIntent({db: f.db, stripe: f.stripe, intent: f.intent, eventType: "payment_intent.succeeded"}), {handled: true});
  assert.equal(f.rows.get("deliveryAdjustments/adj").status, "paid");
  await assert.rejects(handlePaymentIntent({db: f.db, stripe: f.stripe, intent: {...f.intent, id: "pi_wrong"}, eventType: "payment_intent.succeeded"}), /does not match checkout/);
});

test("canceled native intent cannot be reopened or replaced", async () => {
  const f = fixture(); await createPayment(f.args); f.intent.status = "canceled";
  await assert.rejects(createPayment(f.args), /payment is closed/);
  assert.equal(f.creations(), 1);
});
