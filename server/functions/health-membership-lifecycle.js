/* eslint-disable require-jsdoc */
const {FieldValue} = require("firebase-admin/firestore");
const {recordPaymentArtifactReview} = require("./payment-artifact-reconciliation");

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
  if (!membershipRef) {
    return {
      handled: true,
      actionRequired: true,
      ...(await recordPaymentArtifactReview({
        db,
        event,
        artifactType: "health_membership_subscription",
        objectId: subscription.id,
        reason: "unbound_health_membership_subscription",
        details: {subscriptionId: text(subscription.id), senderId: senderId || null},
      })),
    };
  }
  const status = event.type === "customer.subscription.deleted" ? "canceled" : null;
  return {handled: true, ...await claimMembershipEvent(db, event, membershipRef, membershipPatch({subscription, status}))};
}
async function handleHealthInvoiceEvent({db, event}) {
  const invoice = event.data && event.data.object || {};
  const subscriptionId = invoiceSubscriptionId(invoice);
  const membershipRef = await membershipRefForSubscription(db, subscriptionId);
  if (!membershipRef) {
    return {
      handled: true,
      actionRequired: true,
      ...(await recordPaymentArtifactReview({
        db,
        event,
        artifactType: "health_membership_invoice",
        objectId: invoice.id,
        reason: "unbound_health_membership_invoice",
        details: {subscriptionId, invoiceId: text(invoice.id)},
      })),
    };
  }
  const current = (await membershipRef.get()).data() || {};
  const subscription = {id: subscriptionId, customer: invoice.customer, current_period_start: invoice.period_start, current_period_end: invoice.period_end};
  const status = event.type === "invoice.paid" ? "active" : "past_due";
  return {handled: true, ...await claimMembershipEvent(db, event, membershipRef, {...membershipPatch({subscription, invoice, status}), senderId: current.senderId || membershipRef.id})};
}

async function reconcileHealthMembershipEventsCore({db, stripe, limit = 25}) {
  if (!stripe || !stripe.events || typeof stripe.events.retrieve !== "function") {
    throw new Error("Health+ reconciliation requires Stripe event access.");
  }
  const boundedLimit = Math.max(1, Math.min(Number(limit) || 25, 25));
  const snapshot = await db.collection("paymentArtifactReconciliations")
      .where("artifactType", "in", ["health_membership_subscription", "health_membership_invoice"])
      .where("status", "==", "action_required")
      .orderBy("createdAt")
      .limit(boundedLimit)
      .get();
  const counts = {examined: snapshot.size, resolved: 0, stillUnbound: 0, errors: 0};
  for (const document of snapshot.docs) {
    const record = document.data() || {};
    try {
      const event = await stripe.events.retrieve(record.stripeEventId);
      const result = event.type && event.type.startsWith("customer.subscription.") ?
        await handleHealthSubscriptionEvent({db, event}) :
        await handleHealthInvoiceEvent({db, event});
      if (result.actionRequired) {
        counts.stillUnbound += 1;
        continue;
      }
      await document.ref.set({status: "resolved", reviewStatus: "resolved", resolvedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()}, {merge: true});
      counts.resolved += 1;
    } catch (error) {
      counts.errors += 1;
      await document.ref.set({lastErrorCode: text(error && (error.code || error.name), 80) || "reconciliation_error", lastAttemptAt: FieldValue.serverTimestamp()}, {merge: true});
    }
  }
  return counts;
}

module.exports = {membershipStatus, membershipPatch, claimMembershipEvent, invoiceSubscriptionId, handleHealthMembershipCheckoutSession, handleHealthSubscriptionEvent, handleHealthInvoiceEvent, reconcileHealthMembershipEventsCore};
