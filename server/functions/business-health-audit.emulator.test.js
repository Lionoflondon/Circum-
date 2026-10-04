/* eslint-disable max-len, require-jsdoc */
"use strict";
const {test, before, after} = require("node:test");
const assert = require("node:assert/strict");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore, Timestamp} = require("firebase-admin/firestore");
const business = require("./business-access");
const health = require("./health-plus");
const reminders = require("./health-plus-operations")._private.processHealthPlusRemindersCore;
let app; let db;
before(() => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, "Emulator required");
  app = initializeApp({projectId: "demo-business-health-audit"});
  db = getFirestore();
});
after(async () => {
if (app) await deleteApp(app);
});
const context = (uid) => ({auth: {uid, token: {email: `${uid}@example.invalid`}}});

test("self-service Business joining cannot grant privileged roles", async () => {
  await db.doc("businessAccounts/immediate").set({joinPolicy: "immediate", ownerUid: "owner", teamMemberIds: []});
  for (const role of ["owner", "admin", "manager", "finance", "dispatcher"]) {
    await assert.rejects(business.requestBusinessAccess.run({businessId: "immediate", role}, context(`attacker-${role}`)), {code: "permission-denied"});
    assert.equal((await db.doc(`businessMemberships/immediate_attacker-${role}`).get()).exists, false);
  }
  assert.equal((await business.requestBusinessAccess.run({businessId: "immediate", role: "member"}, context("member"))).status, "joined");
});

test("suspension revokes Business admin actions, stale manager review and read membership IDs", async () => {
  await db.doc("businessAccounts/suspension").set({createdByUserId: "owner", ownerUid: "owner", managerIds: ["admin"], teamMemberIds: ["admin"], teamMembers: [{userId: "admin", email: "admin@example.invalid", role: "admin", status: "active"}]});
  await business.updateBusinessMemberStatus.run({businessId: "suspension", memberUserId: "admin", status: "suspended"}, context("owner"));
  const account = (await db.doc("businessAccounts/suspension").get()).data();
  assert.deepEqual(account.teamMemberIds, []);
  assert.deepEqual(account.managerIds, []);
  assert.equal((await db.doc("businessMemberships/suspension_admin").get()).data().status, "suspended");
  await assert.rejects(business.updateBusinessProfile.run({businessId: "suspension"}, context("admin")), {code: "permission-denied"});
  await db.doc("businessAccounts/suspension").set({managerIds: ["admin"]}, {merge: true});
  await db.doc("businessJoinRequests/review").set({businessId: "suspension", userId: "new", roleRequested: "member"});
  await assert.rejects(business.reviewBusinessAccessRequest.run({requestId: "review", approved: true}, context("admin")), {code: "permission-denied"});
});

test("Health+ action replay is owned, target-bound and pause-resume-pause applies again", async () => {
  await db.doc("recurringPickupSchedules/schedule").set({senderId: "owner", status: "active", paused: false});
  const pause = {action: "pause_schedule", scheduleId: "schedule", idempotencyKey: "pause"};
  await health.updateSenderHealthPlusBooking.run(pause, context("owner"));
  await assert.rejects(health.updateSenderHealthPlusBooking.run(pause, context("stranger")), {code: "permission-denied"});
  await assert.rejects(health.updateSenderHealthPlusBooking.run({...pause, scheduleId: "different"}, context("owner")), {code: "permission-denied"});
  assert.equal((await health.updateSenderHealthPlusBooking.run(pause, context("owner"))).idempotent, true);
  await health.updateSenderHealthPlusBooking.run({action: "resume_schedule", scheduleId: "schedule", idempotencyKey: "resume"}, context("owner"));
  await health.updateSenderHealthPlusBooking.run(pause, context("owner"));
  assert.equal((await db.doc("recurringPickupSchedules/schedule").get()).data().status, "paused");
  await health.updateSenderHealthPlusBooking.run({action: "cancel_schedule", scheduleId: "schedule", idempotencyKey: "cancel"}, context("owner"));
  await assert.rejects(health.updateSenderHealthPlusBooking.run({action: "resume_schedule", scheduleId: "schedule", idempotencyKey: "resume"}, context("owner")), {code: "failed-precondition"});
});

test("Health+ reminders scan past 300 ineligible pickups and escalate a later overdue pickup", async () => {
  const now = new Date("2026-10-04T12:00:00Z");
  const batch = db.batch();
  for (let i = 0; i < 301; i++) batch.set(db.doc(`prescriptionPickups/a${String(i).padStart(3, "0")}`), {status: "scheduled", scheduledAt: Timestamp.fromDate(new Date("2026-12-01T12:00:00Z"))});
  batch.set(db.doc("prescriptionPickups/z-overdue"), {senderId: "owner", status: "scheduled", scheduledAt: Timestamp.fromDate(new Date("2026-10-04T11:00:00Z"))});
  await batch.commit();
  const result = await reminders(db, now);
  assert.equal(result.scanned, 302);
  assert.equal(result.escalated, 1);
  assert.equal((await db.doc("prescriptionPickups/z-overdue").get()).data().status, "escalated");
});


test("out-of-order Health+ billing events cannot restore cancelled or stale entitlements", async () => {
  const lifecycle = require("./health-membership-lifecycle");
  const subscription = {id: "sub_ordered", customer: "cus_ordered", status: "active", metadata: {userId: "ordered-owner"}};
  const event = (id, type, created, object) => ({id, type, created, data: {object}});
  await lifecycle.handleHealthSubscriptionEvent({db, event: event("evt_active", "customer.subscription.updated", 100, subscription)});
  await lifecycle.handleHealthSubscriptionEvent({db, event: event("evt_cancel", "customer.subscription.deleted", 200, {...subscription, status: "canceled"})});
  const stale = await lifecycle.handleHealthSubscriptionEvent({db, event: event("evt_old_active", "customer.subscription.updated", 150, subscription)});
  assert.equal(stale.suppressed, true);
  const invoice = {id: "in_old", subscription: "sub_ordered", customer: "cus_ordered"};
  const paid = await lifecycle.handleHealthInvoiceEvent({db, event: event("evt_paid_after_cancel", "invoice.paid", 250, invoice)});
  assert.equal(paid.suppressed, true);
  assert.equal((await db.doc("healthPlusMemberships/ordered-owner").get()).data().status, "canceled");
  assert.equal((await lifecycle.handleHealthInvoiceEvent({db, event: event("evt_paid_after_cancel", "invoice.paid", 250, invoice)})).duplicate, true);
});


test("Business atomic invoice payment preserves zero against stale available balance", async () => {
  const pay = require("./business-payments")._private.payBusinessInvoiceAtomically;
  await db.doc("businessAccounts/zero-wallet").set({ownerUid: "owner"});
  await db.doc("business_wallets/zero-wallet").set({balance: 0, availableBalance: 99, reservedBalance: 0});
  await db.doc("businessInvoices/zero-wallet").set({businessId: "zero-wallet", total: 10, balanceDue: 10, amountPaid: 0, status: "unpaid"});
  await assert.rejects(pay({db, businessId: "zero-wallet", invoiceId: "zero-wallet", rothAmount: 10, method: "roth"}), {code: "failed-precondition"});
  assert.equal((await db.doc("business_wallets/zero-wallet").get()).data().balance, 0);
  assert.equal((await db.doc("businessInvoices/zero-wallet").get()).data().status, "unpaid");
});

test("Health+ paid checkout finalization is atomic, concurrent-idempotent and repairs a legacy partial commit", async () => {
  const bookingId = "atomic-health";
  const payment = {senderId: "owner", profileId: "owner", pricingAuthorityVersion: 2, checkoutSessionId: "cs_atomic", cardAmount: 11, rothAmount: 0, amountPence: 1100};
  await db.doc(`prescriptionPickups/${bookingId}`).set({senderId: "owner", profileId: "owner", status: "scheduled"});
  await db.doc(`healthPlusPayments/${bookingId}`).set(payment);
  const session = {id: "cs_atomic", payment_status: "paid", status: "complete", amount_total: 1100, currency: "gbp", payment_intent: "pi_atomic", metadata: {bookingId, profileId: "owner", userId: "owner"}};
  await Promise.all(Array.from({length: 20}, (_, i) => health._qaHandlers.handleHealthPlusCheckoutSessionHandler(session, `evt_atomic_${i}`, {db})));
  assert.equal((await db.doc(`prescriptionPickups/${bookingId}`).get()).data().paymentStatus, "paid");
  assert.equal((await db.doc(`healthPlusPayments/${bookingId}`).get()).data().status, "paid");
  assert.equal((await db.collection("healthPlusUsageEvents").where("pickupId", "==", bookingId).where("type", "==", "checkout_paid").get()).size, 1);
  await db.doc(`prescriptionPickups/${bookingId}`).set({paymentStatus: "unpaid"}, {merge: true});
  await health._qaHandlers.handleHealthPlusCheckoutSessionHandler(session, "evt_atomic_repair", {db});
  assert.equal((await db.doc(`prescriptionPickups/${bookingId}`).get()).data().paymentStatus, "paid");
});


test("Business email invitations require verified email ownership", async () => {
  await db.doc("businessAccounts/invitation").set({ownerUid: "owner", teamMemberIds: ["invited@example.invalid"], teamMembers: [{userId: "invited@example.invalid", email: "invited@example.invalid", role: "admin", status: "invited"}]});
  const unverified = {auth: {uid: "invitee", token: {email: "invited@example.invalid", email_verified: false}}};
  await assert.rejects(business.updateBusinessProfile.run({businessId: "invitation", businessName: "Example", contactEmail: "owner@example.invalid"}, unverified), {code: "permission-denied"});
  const verified = {auth: {uid: "invitee", token: {...unverified.auth.token, email_verified: true}}};
  assert.equal((await business.updateBusinessProfile.run({businessId: "invitation", businessName: "Example", contactEmail: "owner@example.invalid"}, verified)).status, "updated");
});


test("Operations member removal revokes IDs and canonical membership; missing reason cannot mutate", async () => {
  const admin = require("./admin-operations-authority");
  const adminContext = {auth: {uid: "operator", token: {adminRole: "operations_admin"}}, app: {appId: "emulator"}};
  await db.doc("businessAccounts/admin-remove").set({ownerUid: "owner", teamMemberIds: ["member"], managerIds: ["member"], teamMembers: [{userId: "member", role: "admin", status: "active"}]});
  await db.doc("businessMemberships/admin-remove_member").set({businessId: "admin-remove", userId: "member", role: "admin", status: "active"});
  await assert.rejects(admin.adminUpdateBusinessMember.run({businessId: "admin-remove", memberIndex: 0, remove: true}, adminContext), {code: "invalid-argument"});
  assert.equal((await db.doc("businessAccounts/admin-remove").get()).data().teamMembers.length, 1);
  await admin.adminUpdateBusinessMember.run({businessId: "admin-remove", memberIndex: 0, remove: true, reason: "Synthetic regression"}, adminContext);
  const record = (await db.doc("businessAccounts/admin-remove").get()).data();
  assert.deepEqual(record.teamMemberIds, []);
  assert.deepEqual(record.managerIds, []);
  assert.equal((await db.doc("businessMemberships/admin-remove_member").get()).data().status, "removed");
});


test("missing Business targets return a validation error before Firestore access", async () => {
  for (const operation of ["requestBusinessAccess", "reviewBusinessAccessRequest", "updateBusinessProfile", "recordBusinessIrisMoment"]) {
    await assert.rejects(business[operation].run({}, context("owner")), {code: "invalid-argument"});
  }
});

test("a stale reminder snapshot cannot rewind a completed pickup", async () => {
  await db.doc("prescriptionPickups/zz-race").set({senderId: "owner", status: "scheduled", scheduledAt: Timestamp.fromDate(new Date("2026-10-04T11:00:00Z"))});
  const wrap = (query) => new Proxy(query, {get(target, key) {
    if (key === "get") {
return async () => {
      const snapshot = await target.get();
      if (snapshot.docs.some((record) => record.id === "zz-race")) await db.doc("prescriptionPickups/zz-race").set({status: "delivered"}, {merge: true});
      return snapshot;
    };
}
    if (["where", "orderBy", "limit", "startAfter"].includes(key)) return (...args) => wrap(target[key](...args));
    return typeof target[key] === "function" ? target[key].bind(target) : target[key];
  }});
  const racingDb = {collection: (name) => name === "prescriptionPickups" ? wrap(db.collection(name)) : db.collection(name), runTransaction: db.runTransaction.bind(db)};
  assert.equal((await reminders(racingDb, new Date("2026-10-04T12:00:00Z"))).escalated, 0);
  assert.equal((await db.doc("prescriptionPickups/zz-race").get()).data().status, "delivered");
});

test("a Health+ booking replay cannot return another Sender's record", async (t) => {
  process.env.GOOGLE_MAPS_DIRECTIONS_API_KEY = "emulator-test";
  t.mock.method(global, "fetch", async () => ({ok: true, json: async () => ({routes: [{distanceMeters: 3218.688}]})}));
  const input = {consentConfirmed: true, fullName: "Synthetic Sender", phoneNumber: "07000000000", pharmacyAddress: "Pharmacy", deliveryAddress: "Home", preferredPickupTime: "2026-10-05T10:00:00Z", frequency: "one_off", pricingInputs: {medicationWeightKg: 1}, idempotencyKey: "shared-booking-key"};
  await health.createHealthPlusBooking.run(input, context("owner"));
  await assert.rejects(health.createHealthPlusBooking.run(input, context("stranger")), {code: "permission-denied"});
});


test("zero Business invoice totals cannot fall back to stale amounts or debit a wallet", async () => {
  const payments = require("./business-payments");
  const invoiceId = "zero-invoice-total";
  await db.doc(`businessInvoices/${invoiceId}`).set({businessId: invoiceId, total: 0, subtotal: 99, balanceDue: 10, amountPaid: 0, status: "unpaid"});
  await db.doc(`business_wallets/${invoiceId}`).set({balance: 20, availableBalance: 20, reservedBalance: 0});
  await assert.rejects(payments._private.payBusinessInvoiceAtomically({db, businessId: invoiceId, invoiceId, rothAmount: 10, method: "roth"}), {code: "failed-precondition"});
  await assert.rejects(payments._private.markInvoicePaid({businessId: invoiceId, invoiceId, amount: 10, method: "card"}), {code: "failed-precondition"});
  assert.equal((await db.doc(`business_wallets/${invoiceId}`).get()).data().balance, 20);
  assert.equal((await db.doc(`businessInvoices/${invoiceId}`).get()).data().status, "unpaid");
  const admin = {auth: {uid: "admin", token: {admin: true, role: "super_admin"}}, app: {appId: "audit"}};
  await assert.rejects(payments.adminCreateBusinessInvoice.run({businessId: invoiceId, total: 0, amount: 10, reason: "Zero validation"}, admin), {code: "invalid-argument"});
});


test("cancelled Health+ membership resists equal/later stale activation but permits a paid replacement subscription", async () => {
  const lifecycle = require("./health-membership-lifecycle");
  const senderId = "terminal-membership-owner";
  const event = (id, type, created, object) => ({id, type, created, data: {object}});
  const old = {id: "sub_terminal_old", customer: "cus_terminal", status: "active", metadata: {userId: senderId}};
  await lifecycle.handleHealthSubscriptionEvent({db, event: event("evt_terminal_active", "customer.subscription.updated", 100, old)});
  await lifecycle.handleHealthSubscriptionEvent({db, event: event("evt_terminal_deleted", "customer.subscription.deleted", 200, {...old, status: "canceled"})});
  for (const created of [200, 201]) {
    const result = await lifecycle.handleHealthSubscriptionEvent({db, event: event(`evt_terminal_late_${created}`, "customer.subscription.updated", created, old)});
    assert.equal(result.suppressed, true);
    assert.equal((await db.doc(`healthPlusMemberships/${senderId}`).get()).data().status, "canceled");
  }
  const session = {id: "cs_terminal_new", mode: "subscription", subscription: "sub_terminal_new", customer: "cus_terminal", payment_status: "paid", metadata: {type: "health_plus_payment", userId: senderId}};
  const replacement = await lifecycle.handleHealthMembershipCheckoutSession({db, session, event: event("evt_terminal_replacement", "checkout.session.completed", 202, session)});
  assert.equal(replacement.suppressed, undefined);
  const current = {...old, id: "sub_terminal_new"};
  await lifecycle.handleHealthSubscriptionEvent({db, event: event("evt_terminal_new_active", "customer.subscription.updated", 203, current)});
  const membership = (await db.doc(`healthPlusMemberships/${senderId}`).get()).data();
  assert.equal(membership.status, "active");
  assert.equal(membership.stripeSubscriptionId, "sub_terminal_new");
});


test("Health+ checkout blocks an existing subscription before charging and reuses the cancelled member's customer", async (t) => {
  const uid = "resubscribe-owner";
  const auth = require("firebase-admin/auth").getAuth();
  t.mock.method(auth, "verifyIdToken", async () => ({uid, email: "qa@example.invalid"}));
  process.env.GOOGLE_MAPS_DIRECTIONS_API_KEY = "emulator-test";
  t.mock.method(global, "fetch", async () => ({ok: true, json: async () => ({routes: [{distanceMeters: 3218.688}]})}));
  const bookingId = "resubscribe-booking";
  await db.doc(`prescriptionPickups/${bookingId}`).set({senderId: uid, profileId: uid, status: "scheduled", frequency: "monthly", subscriptionPlan: "core", pricingInputs: {medicationWeightKg: 1}, pharmacyAddress: "Pharmacy", deliveryAddress: "Home", routeAuthorityVersion: 2});
  await db.doc(`healthPlusProfiles/${uid}`).set({senderId: uid});
  const ref = db.doc(`healthPlusMemberships/${uid}`);
  await ref.set({senderId: uid, status: "active", stripeCustomerId: "cus_existing", stripeSubscriptionId: "sub_existing"});
  let calls = 0; let params; let code; let body;
  const stripe = {checkout: {sessions: {create: async (input) => {
    calls++; params = input; return {id: "cs_resubscribe", url: "https://example.invalid/checkout"};
  }, retrieve: async () => ({id: "cs_resubscribe", status: "open", payment_status: "unpaid"})}}};
  const res = {set() {}, status(value) {
code = value; return this;
}, send(value) {
body = value; return this;
}};
  const req = {method: "POST", headers: {authorization: "Bearer emulator-test"}, body: {bookingId, profileId: uid}};
  await health._qaHandlers.createHealthPlusCheckoutHandler(req, res, {db, stripe});
  assert.equal(code, 403);
  assert.equal(body.code, "failed-precondition");
  assert.equal(calls, 0);
  assert.equal((await db.doc(`healthPlusPayments/${bookingId}`).get()).exists, false);
  await ref.set({status: "canceled"}, {merge: true});
  code = 200;
  await health._qaHandlers.createHealthPlusCheckoutHandler(req, res, {db, stripe});
  assert.equal(code, 200);
  assert.equal(calls, 1);
  assert.equal(params.customer, "cus_existing");
  assert.equal(params.customer_email, undefined);
  assert.equal(params.metadata.userId, uid);
  await health._qaHandlers.createHealthPlusCheckoutHandler(req, res, {db, stripe});
  assert.equal(body.idempotent, true);
  assert.equal(calls, 1);
});


test("legacy Health+ status control enforces clinical Operations permissions and atomic audited updates", async (t) => {
  const uid = "health-operations-admin";
  let token = {uid, role: "finance_admin"};
  t.mock.method(require("firebase-admin/auth").getAuth(), "verifyIdToken", async () => token);
  const pickupId = "clinical-control";
  await db.doc(`prescriptionPickups/${pickupId}`).set({status: "scheduled"});
  let code; let body;
  const res = {set() {}, status(value) {
code = value; return this;
}, send(value) {
body = value; return this;
}};
  const req = {method: "POST", headers: {authorization: "Bearer emulator-test"}, body: {pickupId, status: "assigned", adminId: "spoofed", note: "Controlled Operations check"}};
  for (const role of ["finance_admin", "support_agent", "driver_manager", "owner"]) {
    token = {uid, role};
    await health.updateHealthPlusPickupStatus(req, res);
    assert.equal(code, 403);
    assert.equal(body.code, "permission-denied");
    assert.equal((await db.doc(`prescriptionPickups/${pickupId}`).get()).data().status, "scheduled");
  }
  token = {uid, role: "operations_admin"};
  await health.updateHealthPlusPickupStatus({...req, body: {...req.body, pickupId: "missing-clinical-control"}}, res);
  assert.equal(body.code, "not-found");
  assert.equal((await db.doc("prescriptionPickups/missing-clinical-control").get()).exists, false);
  code = 200;
  await health.updateHealthPlusPickupStatus(req, res);
  assert.equal(code, 200);
  const pickup = (await db.doc(`prescriptionPickups/${pickupId}`).get()).data();
  assert.equal(pickup.status, "assigned");
  assert.equal(pickup.lastAdminId, uid);
  const events = await db.collection("healthPlusUsageEvents").where("pickupId", "==", pickupId).get();
  assert.equal(events.size, 1);
  assert.equal(events.docs[0].data().adminId, uid);
  assert.equal(events.docs[0].data().previousStatus, "scheduled");
});
