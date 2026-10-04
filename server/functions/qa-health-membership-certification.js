/* eslint-disable max-len, require-jsdoc */
"use strict";
const lifecycle = require("./health-membership-lifecycle");
const checkoutAuthority = require("./health-checkout-authority");
async function certify({db, senderId}) {
  const checks = [];
  const check = (name, pass) => {
 if (!pass) throw new Error(`Health+ private certification failed: ${name}`); checks.push(name);
};
  const event = (id, type, created, object) => ({id, type, created, data: {object}});
  const sub = {id: "sub_qa_health", customer: "cus_qa_health", status: "active", metadata: {userId: senderId}, current_period_start: 100, current_period_end: 1000, cancel_at_period_end: true, items: {data: [{price: {id: "price_qa_health"}}]}};
  const session = {id: "cs_qa_health", mode: "subscription", subscription: sub.id, customer: sub.customer, payment_status: "paid", metadata: {type: "health_plus_payment", userId: senderId}};
  await lifecycle.handleHealthSubscriptionEvent({db, event: event("evt_qa_active", "customer.subscription.updated", 200, sub)});
  await lifecycle.handleHealthMembershipCheckoutSession({db, session, event: event("evt_qa_checkout", "checkout.session.completed", 300, session)});
  const ref = db.doc(`healthPlusMemberships/${senderId}`);
  check("delayed_checkout_preserves_active", (await ref.get()).data().status === "active");
  await lifecycle.handleHealthInvoiceEvent({db, event: event("evt_qa_invoice", "invoice.paid", 400, {id: "in_qa_health", subscription: sub.id, customer: sub.customer})});
  const current = (await ref.get()).data();
  check("partial_invoice_preserves_period_and_plan", current.currentPeriodEnd.toMillis() === 1000000 && current.planId === "price_qa_health" && current.cancelAtPeriodEnd === true);
  await lifecycle.handleHealthSubscriptionEvent({db, event: event("evt_qa_cancel", "customer.subscription.deleted", 500, sub)});
  const replacement = {...session, id: "cs_qa_new", subscription: "sub_qa_new"};
  await lifecycle.handleHealthMembershipCheckoutSession({db, session: replacement, event: event("evt_qa_replace", "checkout.session.completed", 700, replacement)});
  await lifecycle.handleHealthSubscriptionEvent({db, event: event("evt_qa_new_active", "customer.subscription.updated", 600, {...sub, id: replacement.subscription})});
  const retired = event("evt_qa_retired", "customer.subscription.deleted", 800, sub);
  check("retired_subscription_suppressed", (await lifecycle.handleHealthSubscriptionEvent({db, event: retired})).suppressed === true);
  check("event_replay_idempotent", (await lifecycle.handleHealthSubscriptionEvent({db, event: retired})).duplicate === true);
  check("replacement_subscription_active", (await ref.get()).data().status === "active");
  const claimSender = `${senderId}_claim`;
  const bookings = ["qa_claim_a", "qa_claim_b"].map((id) => ({id, senderId: claimSender, profileId: claimSender, status: "scheduled", routeAuthorityVersion: 2}));
  for (const booking of bookings) await db.doc(`prescriptionPickups/${booking.id}`).set(booking);
  const results = await Promise.allSettled(bookings.map((booking) => checkoutAuthority.reserve({db, paymentRef: db.doc(`healthPlusPayments/${booking.id}`), booking, candidate: {recurring: true, amountPence: 100}})));
  check("one_sender_one_concurrent_checkout", results.filter((r) => r.status === "fulfilled").length === 1 && results.filter((r) => r.status === "rejected").length === 1);
  return {passed: true, checks, providerEvents: "simulated", providerCalls: 0, isolated: true};
}
module.exports = {certify};
