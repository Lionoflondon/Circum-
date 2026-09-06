/* eslint-disable max-len, require-jsdoc */
"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const health = require("./health-checkout-authority");
const booking = {routeAuthorityVersion: 2, senderId: "owner", profileId: "profile", pharmacyAddress: "A", deliveryAddress: "B", status: "scheduled", pricingInputs: {distanceMiles: 2, medicationWeightKg: 1}, frequency: "one_off"};
function fixture() {
  const records = new Map([["prescriptionPickups/booking", structuredClone(booking)]]);
  const ref = (path) => ({path, id: path.split("/").pop(), set: async (value) => records.set(path, {...records.get(path), ...value})});
  const snap = (r) => ({exists: records.has(r.path), data: () => structuredClone(records.get(r.path))});
  const db = {doc: ref, runTransaction: async (work) => work({get: async (r) => snap(r), getAll: async (...refs) => refs.map(snap), set: (r, value) => records.set(r.path, {...records.get(r.path), ...value})})};
  const paymentRef = ref("healthPlusPayments/booking");
  return {db, paymentRef, records};
}
const candidate = {amountPence: 1000, orderTotalGbp: 10, rothAmount: 3, cardAmount: 7};
test("fresh Health booking reserves one fixed mixed-payment authority", async () => {
  const f = fixture();
  const a = await health.reserve({...f, booking, candidate});
  const b = await health.reserve({...f, booking, candidate: {...candidate, amountPence: 1, rothAmount: 0}});
  assert.deepEqual(a, b);
  assert.equal(a.amountPence, 1000);
  assert.equal(a.rothAmount, 3);
  assert.equal(a.cardAmount, 7);
});
test("Health reservation rejects booking changes between read and transaction", async () => {
  for (const change of [{deliveryAddress: "C"}, {senderId: "foreign"}, {status: "cancelled"}, {status: "expired"}, {pricingInputs: {distanceMiles: 2, medicationWeightKg: 8}}]) {
    const f = fixture();
    f.records.set("prescriptionPickups/booking", {...booking, ...change});
    await assert.rejects(health.reserve({...f, booking, candidate}), /booking changed/);
    assert.equal(f.records.has(f.paymentRef.path), false);
  }
});
test("Health rejects a frozen authority from an earlier route", async () => {
  const f = fixture();
  await health.reserve({...f, booking, candidate});
  const changed = {...booking, pharmacyAddress: "Other pharmacy"};
  f.records.set("prescriptionPickups/booking", changed);
  await assert.rejects(health.reserve({...f, booking: changed, candidate}), /fresh booking/);
});
test("Health rejects legacy unbound authority before provider creation", async () => {
  const f = fixture();
  f.records.set(f.paymentRef.path, {checkoutAuthority: candidate});
  await assert.rejects(health.reserve({...f, booking, candidate}), /fresh booking/);
});
test("Health rechecks cancellation before creating provider parameters", async () => {
  const f = fixture();
  await health.reserve({...f, booking, candidate});
  f.records.set("prescriptionPickups/booking", {...booking, status: "cancelled"});
  let called = false;
  const stripe = {checkout: {sessions: {create: async () => {
called = true;
}}}};
  await assert.rejects(health.create({...f, booking, stripe, params: {}, record: {}}), /booking changed/);
  assert.equal(called, false);
});
test("Health refuses stale provider-session reuse despite v2 booking", async () => {
  const f = fixture();
  let expired = false;
  const session = {id: "old", status: "open", payment_status: "unpaid", metadata: {bookingId: "booking", type: "health_plus_payment"}};
  const stripe = {checkout: {sessions: {retrieve: async () => session, list: async () => ({data: [session], has_more: false}), expire: async () => {
expired = true; return {...session, status: "expired"};
}}}};
  await assert.rejects(health.legacyGate({...f, stripe, bookingId: "booking", booking, payment: {checkoutSessionId: "old", pricingAuthorityVersion: 2, checkoutAuthority: {...candidate, bookingBinding: "old-route"}}}), /fresh route price/);
  assert.equal(expired, true);
});
