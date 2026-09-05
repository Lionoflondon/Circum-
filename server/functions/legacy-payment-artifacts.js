/* eslint-disable max-len, require-jsdoc */
const functions = require("firebase-functions/v1");
const blocked = (message, reason) =>
  new functions.https.HttpsError("failed-precondition", message, {reason});
// Listing also finds sessions created before an older process persisted their IDs.
async function expireLegacySessions({stripe, matches, knownIds = []}) {
  const sessions = new Map();
  for (const id of knownIds.filter(Boolean)) {
    sessions.set(id, await stripe.checkout.sessions.retrieve(id));
  }
  let cursor;
  for (let page = 0; page < 100; page++) {
    const result = await stripe.checkout.sessions.list({
      limit: 100,
      ...(cursor ? {starting_after: cursor} : {}),
    });
    for (const session of result.data) {
      if (matches(session)) sessions.set(session.id, session);
    }
    if (!result.has_more) break;
    if (page === 99 || !result.data.length) {
      throw blocked(
        "Payment inventory is incomplete. Retry after reconciliation.",
        "legacy_inventory_incomplete",
      );
    }
    cursor = result.data[result.data.length - 1].id;
  }
  for (let session of sessions.values()) {
    if (session.status === "open" && session.payment_status !== "paid") {
      session = await stripe.checkout.sessions.expire(session.id);
    }
    if (session.status !== "expired") {
      throw blocked(
        "An earlier payment requires reconciliation before another checkout can be created.",
        "legacy_payment_reconciliation_required",
      );
    }
  }
  return [...sessions.keys()];
}
async function rejectLegacySenderQuote({db, stripe, quote, quoteId, senderId}) {
  if (quote.parcelAuthority) return;
  const ref = db.doc(`senderPaymentSessions/${quoteId}`);
  const snap = await ref.get();
  const payment = snap.data() || {};
  const review = async (reason) =>
    db.doc(`paymentArtifactReconciliations/sender_${quoteId}`).set(
      {
        service: "sender",
        quoteId,
        senderId,
        reason,
        status: "review_required",
        updatedAt: Date.now(),
      },
      {merge: true},
    );
  try {
    if (
      payment.status === "succeeded" ||
      payment.paymentStatus === "succeeded"
    ) {
      throw blocked(
        "Earlier payment requires reconciliation.",
        "legacy_payment_reconciliation_required",
      );
    }
    await expireLegacySessions({
      stripe,
      knownIds: [payment.checkoutSessionId],
      matches: (s) =>
        s.metadata &&
        s.metadata.quoteId === quoteId &&
        s.metadata.userId === senderId,
    });
    if (payment.stripePaymentIntentId) {
      let intent = await stripe.paymentIntents.retrieve(
        payment.stripePaymentIntentId,
      );
      if (
        [
          "requires_payment_method",
          "requires_confirmation",
          "requires_action",
          "requires_capture",
        ].includes(intent.status)
      ) {
        intent = await stripe.paymentIntents.cancel(intent.id);
      }
      if (intent.status !== "canceled") {
        throw blocked(
          "Earlier payment requires reconciliation.",
          "legacy_payment_reconciliation_required",
        );
      }
    }
  } catch (error) {
    await review(
      (error.details && error.details.reason) || "provider_state_unconfirmed",
    );
    throw error;
  }
  await db.doc(`senderBookingQuotes/${quoteId}`).set(
    {
      paymentRegenerationRequired: true,
      invalidationReason: "missing_parcel_authority",
      updatedAt: Date.now(),
    },
    {merge: true},
  );
  throw blocked(
    "This quote needs a new parcel safety check. Request a new quote before paying.",
    "quote_regeneration_required",
  );
}
module.exports = {expireLegacySessions, rejectLegacySenderQuote, blocked};
