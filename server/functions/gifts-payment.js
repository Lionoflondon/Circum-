/* eslint-disable max-len, require-jsdoc */
const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");

function requireAuth(context) {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in to continue with Gifts by Circum.");
  }
}

exports.createGiftPayment = (stripe) => functions.https.onCall(async (data, context) => {
  requireAuth(context);
  const giftDraftId = String(data.giftDraftId || "");
  const ref = getFirestore().collection("giftPaymentDrafts").doc(giftDraftId);
  const snap = await ref.get();
  if (!snap.exists || snap.data().senderId !== context.auth.uid) {
    throw new functions.https.HttpsError("not-found", "Gift draft not found.");
  }
  const gift = snap.data();
  const gross = Number(gift.grossGiftBudget || gift.grossBudget || 0);
  if (gross < 50 || gift.paymentStatus === "paid") {
    throw new functions.https.HttpsError("failed-precondition", "Gift payment cannot be started.");
  }
  const config = functions.config().gifts || {};
  const baseUrl = "https://circumuk.com/?app=gifts";
  const successUrl = config.success_url || `${baseUrl}&gift_payment=success&giftDraftId=${giftDraftId}&session_id={CHECKOUT_SESSION_ID}`;
  const cancelUrl = config.cancel_url || `${baseUrl}&gift_payment=cancelled&giftDraftId=${giftDraftId}`;
  let session;
  try {
    session = await stripe.checkout.sessions.create({
      mode: "payment",
      customer_email: gift.senderEmail,
      line_items: [{
        quantity: 1,
        price_data: {
          currency: "gbp",
          unit_amount: Math.round(gross * 100),
          product_data: {
            name: "Gifts by Circum experience",
            description: `${gift.occasion || "Curated"} gift experience for ${gift.recipientName || "recipient"}`,
          },
        },
      }],
      success_url: successUrl,
      cancel_url: cancelUrl,
      metadata: {giftDraftId, senderId: context.auth.uid, type: "gift_experience"},
    });
  } catch (error) {
    console.error("createGiftPayment Stripe Checkout error", error);
    throw new functions.https.HttpsError("internal", "Could not start Stripe Checkout. Please try again.");
  }
  await ref.update({
    paymentStatus: "payment_pending",
    stripeCheckoutSessionId: session.id,
    updatedAt: FieldValue.serverTimestamp(),
  });
  return {url: session.url, sessionId: session.id};
});

async function finalizeGiftPaymentSession({
  giftDraftId,
  session,
  actorUid = null,
  eventId = null,
}) {
  const db = getFirestore();
  const draftRef = db.collection("giftPaymentDrafts").doc(giftDraftId);
  const giftRef = db.collection("giftRequests").doc(giftDraftId);
  if (!session || session.payment_status !== "paid") {
    throw new functions.https.HttpsError("failed-precondition", "Payment has not completed.");
  }
  return db.runTransaction(async (transaction) => {
    const [draftSnap, existingGiftSnap] = await Promise.all([
      transaction.get(draftRef),
      transaction.get(giftRef),
    ]);
    if (existingGiftSnap.exists) {
      const existing = existingGiftSnap.data() || {};
      if (existing.paymentStatus === "paid") {
        return {paymentStatus: "paid", giftStatus: "submitted_for_review", giftRequestId: giftDraftId};
      }
      throw new functions.https.HttpsError("failed-precondition", "Gift request already exists in a non-payable state.");
    }
    if (!draftSnap.exists) {
      throw new functions.https.HttpsError("not-found", "Gift draft not found.");
    }
    const gift = draftSnap.data() || {};
    if (actorUid && gift.senderId !== actorUid) {
      throw new functions.https.HttpsError("permission-denied", "Gift draft does not belong to this account.");
    }
    if (session.id !== gift.stripeCheckoutSessionId) {
      throw new functions.https.HttpsError("invalid-argument", "Invalid checkout session.");
    }
    const gross = Number(gift.grossGiftBudget || gift.grossBudget || 0);
    const expectedAmount = Math.round(gross * 100);
    if (session.currency !== "gbp" || Number(session.amount_total || 0) !== expectedAmount) {
      throw new functions.https.HttpsError("failed-precondition", "Gift payment amount does not match the order.");
    }
    transaction.set(giftRef, {
      ...gift,
      paymentStatus: "paid",
      giftStatus: "submitted_for_review",
      status: "submitted_for_review",
      stripeCheckoutSessionId: session.id,
      stripePaymentIntentId: session.payment_intent,
      stripePaymentEventId: eventId,
      paidAt: FieldValue.serverTimestamp(),
      createdAt: gift.createdAt || FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.set(db.collection("giftPaymentEvents").doc(eventId || `client_${session.id}`), {
      eventId: eventId || null,
      giftDraftId,
      stripeCheckoutSessionId: session.id,
      stripePaymentIntentId: session.payment_intent || null,
      paymentStatus: "paid",
      source: eventId ? "stripe_webhook" : "client_recovery",
      createdAt: FieldValue.serverTimestamp(),
    }, {merge: false});
    transaction.delete(draftRef);
    return {paymentStatus: "paid", giftStatus: "submitted_for_review", giftRequestId: giftDraftId};
  });
}

exports.finalizeGiftPayment = (stripe) => functions.https.onCall(async (data, context) => {
  requireAuth(context);
  const giftDraftId = String(data.giftDraftId || "");
  const sessionId = String(data.sessionId || "");
  const db = getFirestore();
  const snap = await db.collection("giftPaymentDrafts").doc(giftDraftId).get();
  const existing = await db.collection("giftRequests").doc(giftDraftId).get();
  if (!snap.exists && existing.exists && existing.data().senderId === context.auth.uid && existing.data().paymentStatus === "paid") {
    return {paymentStatus: "paid", giftStatus: "submitted_for_review", giftRequestId: giftDraftId};
  }
  if (!snap.exists || snap.data().senderId !== context.auth.uid) {
    throw new functions.https.HttpsError("not-found", "Gift draft not found.");
  }
  if (!sessionId || sessionId !== snap.data().stripeCheckoutSessionId) {
    throw new functions.https.HttpsError("invalid-argument", "Invalid checkout session.");
  }
  const session = await stripe.checkout.sessions.retrieve(sessionId);
  return finalizeGiftPaymentSession({
    giftDraftId,
    session,
    actorUid: context.auth.uid,
  });
});

exports.finalizeGiftPaymentFromCheckoutSession = finalizeGiftPaymentSession;
