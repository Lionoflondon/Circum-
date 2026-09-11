/* eslint-disable require-jsdoc */
const {FieldValue} = require("firebase-admin/firestore");

function text(value) {
 return `${value || ""}`.trim();
}
function dateFromUnix(value) {
  const seconds = Number(value || 0);
  return Number.isFinite(seconds) && seconds > 0 ? new Date(seconds * 1000) : null;
}
function membershipStatus(subscription) {
  if (subscription && subscription.pause_collection) return "paused";
  switch (text(subscription && subscription.status).toLowerCase()) {
    case "active": case "trialing": return "active";
    case "past_due": return "past_due";
    case "canceled": case "incomplete_expired": return "canceled";
    case "unpaid": case "incomplete": return "unpaid";
    default: return "unpaid";
  }
}
function membershipPatch({subscription = {}, invoice = null, status = null}) {
  return {
    status: status || membershipStatus(subscription),
    currentPeriodStart: dateFromUnix(subscription.current_period_start),
    currentPeriodEnd: dateFromUnix(subscription.current_period_end),
    stripeCustomerId: text(subscription.customer) || null,
    stripeSubscriptionId: text(subscription.id) || null,
    latestInvoiceId: text((invoice && invoice.id) || subscription.latest_invoice) || null,
    cancelAtPeriodEnd: subscription.cancel_at_period_end === true,
    planId: text(subscription.items && subscription.items.data && subscription.items.data[0] && subscription.items.data[0].price && subscription.items.data[0].price.id) || null,
    updatedAt: FieldValue.serverTimestamp(),
  };
}
async function claimMembershipEvent(db, event, membershipRef, patch) {
  const eventId = text(event && event.id);
  if (!eventId) throw new Error("Health+ Stripe event id is missing.");
  const eventRef = db.collection("healthPlusMembershipEvents").doc(eventId);
  return db.runTransaction(async (transaction) => {
    if ((await transaction.get(eventRef)).exists) return {duplicate: true, eventId};
    const membershipSnap = await transaction.get(membershipRef);
    const existing = membershipSnap.exists ? membershipSnap.data() || {} : {};
    for (const field of ["senderId", "stripeCustomerId", "stripeSubscriptionId"]) {
      if (text(existing[field]) && text(patch[field]) && text(existing[field]) !== text(patch[field])) {
        throw new Error(`Health+ membership ${field} does not match its existing binding.`);
      }
    }
    transaction.set(membershipRef, patch, {merge: true});
    transaction.create(eventRef, {eventId, type: text(event.type), membershipId: membershipRef.id, createdAt: FieldValue.serverTimestamp()});
    return {duplicate: false, eventId};
  });
}

function invoiceSubscriptionId(invoice) {
  return text(invoice && invoice.subscription) ||
    text(invoice && invoice.parent && invoice.parent.subscription_details && invoice.parent.subscription_details.subscription);
}
async function membershipRefForSubscription(db, subscriptionId) {
  const id = text(subscriptionId);
  if (!id) return null;
  const matches = await db.collection("healthPlusMemberships").where("stripeSubscriptionId", "==", id).limit(1).get();
  return matches.empty ? null : matches.docs[0].ref;
}
async function handleHealthMembershipCheckoutSession({db, session, event}) {
  if (session.mode !== "subscription" || !text(session.subscription)) return {handled: false};
  const senderId = text(session.metadata && session.metadata.userId);
  if (!senderId) throw new Error("Health+ subscription checkout is missing its Sender identity.");
  const subscription = {id: session.subscription, customer: session.customer, status: "incomplete"};
  const patch = {...membershipPatch({subscription, status: "unpaid"}), senderId, checkoutSessionId: text(session.id), profileId: text(session.metadata && session.metadata.profileId) || null, createdAt: FieldValue.serverTimestamp()};
  return {handled: true, ...await claimMembershipEvent(db, event, db.collection("healthPlusMemberships").doc(senderId), patch)};
}
async function handleHealthSubscriptionEvent({db, event}) {
  const subscription = event.data && event.data.object || {};
  const senderId = text(subscription.metadata && subscription.metadata.userId);
  const membershipRef = senderId ? db.collection("healthPlusMemberships").doc(senderId) : await membershipRefForSubscription(db, subscription.id);
  if (!membershipRef) throw new Error("Health+ subscription has no bound membership.");
  const status = event.type === "customer.subscription.deleted" ? "canceled" : null;
  return {handled: true, ...await claimMembershipEvent(db, event, membershipRef, membershipPatch({subscription, status}))};
}
async function handleHealthInvoiceEvent({db, event}) {
  const invoice = event.data && event.data.object || {};
  const subscriptionId = invoiceSubscriptionId(invoice);
  const membershipRef = await membershipRefForSubscription(db, subscriptionId);
  if (!membershipRef) throw new Error("Health+ invoice has no bound membership.");
  const current = (await membershipRef.get()).data() || {};
  const subscription = {id: subscriptionId, customer: invoice.customer, current_period_start: invoice.period_start, current_period_end: invoice.period_end};
  const status = event.type === "invoice.paid" ? "active" : "past_due";
  return {handled: true, ...await claimMembershipEvent(db, event, membershipRef, {...membershipPatch({subscription, invoice, status}), senderId: current.senderId || membershipRef.id})};
}
module.exports = {membershipStatus, membershipPatch, claimMembershipEvent, invoiceSubscriptionId, handleHealthMembershipCheckoutSession, handleHealthSubscriptionEvent, handleHealthInvoiceEvent};
