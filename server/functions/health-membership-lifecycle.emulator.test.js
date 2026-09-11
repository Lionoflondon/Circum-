const {test, before, after} = require("node:test");
const assert = require("node:assert/strict");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const lifecycle = require("./health-membership-lifecycle");
let app; let db;
before(() => {
 assert.ok(process.env.FIRESTORE_EMULATOR_HOST); app = initializeApp({projectId: "health-membership-lifecycle"}); db = getFirestore();
});
after(async () => deleteApp(app));
const event = (type, id, object) => ({type, id, data: {object}});

test("Health+ membership starts and invoice renewals are exactly once", async () => {
  const session = {id: "cs_health_member", mode: "subscription", subscription: "sub_health", customer: "cus_health", metadata: {userId: "sender-health", profileId: "profile-health"}};
  const started = await lifecycle.handleHealthMembershipCheckoutSession({db, session, event: event("checkout.session.completed", "evt_checkout", session)});
  assert.equal(started.handled, true);
  assert.equal((await db.doc("healthPlusMemberships/sender-health").get()).data().status, "unpaid");
  const invoice = {id: "in_renewal", subscription: "sub_health", customer: "cus_health", period_start: 1000, period_end: 2000};
  await lifecycle.handleHealthInvoiceEvent({db, event: event("invoice.paid", "evt_invoice_paid", invoice)});
  const ref = db.doc("healthPlusMemberships/sender-health");
  const paid = await ref.get();
  assert.equal(paid.data().status, "active");
  assert.equal(paid.data().latestInvoiceId, "in_renewal");
  const updateTime = paid.updateTime.toMillis();
  const replay = await lifecycle.handleHealthInvoiceEvent({db, event: event("invoice.paid", "evt_invoice_paid", invoice)});
  assert.equal(replay.duplicate, true);
  assert.equal((await ref.get()).updateTime.toMillis(), updateTime);
  assert.equal((await db.collection("healthPlusMembershipEvents").where("eventId", "==", "evt_invoice_paid").get()).size, 1);
});

test("Health+ failed payments and cancellation change entitlement without ledger movement", async () => {
  const invoice = {id: "in_failed", subscription: "sub_health", customer: "cus_health", period_start: 2000, period_end: 3000};
  await lifecycle.handleHealthInvoiceEvent({db, event: event("invoice.payment_failed", "evt_invoice_failed", invoice)});
  assert.equal((await db.doc("healthPlusMemberships/sender-health").get()).data().status, "past_due");
  const subscription = {id: "sub_health", customer: "cus_health", status: "canceled", current_period_start: 2000, current_period_end: 3000, metadata: {userId: "sender-health"}};
  await lifecycle.handleHealthSubscriptionEvent({db, event: event("customer.subscription.deleted", "evt_sub_deleted", subscription)});
  assert.equal((await db.doc("healthPlusMemberships/sender-health").get()).data().status, "canceled");
  assert.equal((await db.collection("walletTransactions").get()).empty, true);
});

test("one-off Health+ checkout does not create a membership", async () => {
  const oneOff = {id: "cs_one_off", mode: "payment", metadata: {userId: "sender-one-off"}};
  const result = await lifecycle.handleHealthMembershipCheckoutSession({db, session: oneOff, event: event("checkout.session.completed", "evt_one_off", oneOff)});
  assert.equal(result.handled, false);
  assert.equal((await db.doc("healthPlusMemberships/sender-one-off").get()).exists, false);
});
