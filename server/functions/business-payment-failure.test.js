"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {handleBusinessPaymentIntent} = require("./business-payments");
const {providerParams} = require("./business-checkout-reservations");

test("Checkout propagates the authoritative reservation identity to PaymentIntent webhooks", () => {
  const params = providerParams({
    returnUrl: "https://circumuk.com/?app=business",
    businessId: "business-1", invoiceId: "invoice-1", checkoutReservationId: "reservation-1",
    invoiceNumber: "QA-1", currency: "gbp", externalAmount: 2000, rothReserved: 0,
    amount: 20, createdByUserId: "owner-1", expiresAt: Date.now() + 3600000,
  });
  assert.deepEqual(params.payment_intent_data.metadata, params.metadata);
  assert.equal(params.payment_intent_data.metadata.checkoutReservationId, "reservation-1");
});

function fakeDb(initial = {}) {
  const data = new Map(Object.entries(initial));
  const ref = (collection, id) => ({
    get: async () => {
      const value = data.get(`${collection}/${id}`);
      return {exists: value !== undefined, data: () => value && {...value}};
    },
    set: async (value, options = {}) => {
      const key = `${collection}/${id}`;
      data.set(key, options.merge ? {...(data.get(key) || {}), ...value} : {...value});
    },
  });
  return {
    collection: (collection) => ({doc: (id) => ref(collection, id)}),
    runTransaction: async (work) => work({
      get: (reference) => reference.get(),
      set: (reference, value, options) => reference.set(value, options),
    }),
    read: (collection, id) => data.get(`${collection}/${id}`),
  };
}

function fixture(overrides = {}) {
  return fakeDb({
    "businessCheckoutReservations/reservation-1": {
      businessId: "business-1", invoiceId: "invoice-1", status: "open", ...overrides.reservation,
    },
    "businessInvoicePayments/reservation-1": {
      businessId: "business-1", invoiceId: "invoice-1", status: "pending_verification", ...overrides.payment,
    },
    "businessInvoices/invoice-1": {
      businessId: "business-1", status: "open", balanceDue: 20, billingEmail: "billing@example.test", ...overrides.invoice,
    },
  });
}

function intent(status = "requires_payment_method") {
  return {
    id: "pi-1",
    status,
    metadata: {
      type: "business_invoice_payment",
      checkoutReservationId: "reservation-1",
      businessId: "business-1",
      invoiceId: "invoice-1",
    },
  };
}

test("authoritative definitive failure records state for one downstream email", async () => {
  const db = fixture();
  const result = await handleBusinessPaymentIntent({db, intent: intent(), eventId: "evt-failed", eventType: "payment_intent.payment_failed"});
  assert.equal(result.state, "failed");
  assert.equal(result.communicationPublication, "downstream_eventarc");
  assert.equal(db.read("businessInvoices", "invoice-1").paymentCommunicationState, "failed");
  assert.equal(db.read("businessInvoicePayments", "reservation-1").paymentOutcome, "failed");
  const duplicate = await handleBusinessPaymentIntent({db, intent: intent(), eventId: "evt-failed-replay", eventType: "payment_intent.payment_failed"});
  assert.equal(duplicate.communicationKey, result.communicationKey);
});

test("processing remains neutral and success supersedes a queued failure", async () => {
  const db = fixture();
  const ambiguous = await handleBusinessPaymentIntent({db, intent: intent("processing"), eventId: "evt-processing", eventType: "payment_intent.processing"});
  assert.equal(ambiguous.state, "unconfirmed");
  const success = await handleBusinessPaymentIntent({db, intent: intent("succeeded"), eventId: "evt-success", eventType: "payment_intent.succeeded"});
  assert.equal(success.state, "succeeded");
  assert.equal(db.read("businessInvoices", "invoice-1").paymentCommunicationState, "succeeded");
  const lateFailure = await handleBusinessPaymentIntent({db, intent: intent(), eventId: "evt-late-failure", eventType: "payment_intent.payment_failed"});
  assert.equal(lateFailure.skipped, true);
  assert.equal(lateFailure.reason, "authoritative_success_supersedes_failure");
});

test("processing then definitive failure on the same intent has a new logical email identity", async () => {
  const db = fixture();
  const processing = await handleBusinessPaymentIntent({db, intent: intent("processing"), eventId: "evt-processing", eventType: "payment_intent.processing"});
  const failed = await handleBusinessPaymentIntent({db, intent: intent(), eventId: "evt-failed", eventType: "payment_intent.payment_failed"});
  assert.notEqual(processing.communicationKey, failed.communicationKey);
  assert.match(failed.communicationKey, /:failed$/);
});

test("unbound client-shaped metadata cannot create a Business payment outcome", async () => {
  const db = fixture();
  const result = await handleBusinessPaymentIntent({db, intent: {id: "pi-client", metadata: {type: "business_invoice_payment", checkoutReservationId: "missing"}}, eventId: "evt-client", eventType: "payment_intent.payment_failed"});
  assert.equal(result.handled, true);
  assert.equal(result.skipped, true);
  assert.equal(db.read("businessInvoices", "invoice-1").paymentCommunicationState, undefined);
});
