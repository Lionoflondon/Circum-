/* eslint-disable max-len, require-jsdoc */
const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");

const PREVIEW_EMAIL = "ayojason600@gmail.com";

function requirePreview(context) {
  const email = String(context.auth && context.auth.token.email || "").toLowerCase();
  if (!context.auth || email !== PREVIEW_EMAIL) {
    throw new functions.https.HttpsError("permission-denied", "Gifts by Circum is currently in private preview.");
  }
}

exports.createGiftPayment = (stripe) => functions.https.onCall(async (data, context) => {
  requirePreview(context);
  const giftRequestId = String(data.giftRequestId || "");
  const ref = getFirestore().collection("giftRequests").doc(giftRequestId);
  const snap = await ref.get();
  if (!snap.exists || snap.data().senderId !== context.auth.uid) {
    throw new functions.https.HttpsError("not-found", "Gift request not found.");
  }
  const gift = snap.data();
  const gross = Number(gift.grossGiftBudget || gift.grossBudget || 0);
  if (gross < 50 || gift.paymentStatus === "paid") {
    throw new functions.https.HttpsError("failed-precondition", "Gift payment cannot be started.");
  }
  const intent = await stripe.paymentIntents.create({
    amount: Math.round(gross * 100),
    currency: "gbp",
    payment_method_types: ["card"],
    metadata: {giftRequestId, senderId: context.auth.uid, type: "gift_experience"},
  });
  await ref.update({
    paymentStatus: "payment_pending",
    stripePaymentIntentId: intent.id,
    updatedAt: FieldValue.serverTimestamp(),
  });
  return {clientSecret: intent.client_secret};
});

exports.finalizeGiftPayment = (stripe) => functions.https.onCall(async (data, context) => {
  requirePreview(context);
  const giftRequestId = String(data.giftRequestId || "");
  const ref = getFirestore().collection("giftRequests").doc(giftRequestId);
  const snap = await ref.get();
  if (!snap.exists || snap.data().senderId !== context.auth.uid) {
    throw new functions.https.HttpsError("not-found", "Gift request not found.");
  }
  const gift = snap.data();
  const intent = await stripe.paymentIntents.retrieve(gift.stripePaymentIntentId);
  if (intent.status !== "succeeded") {
    await ref.update({paymentStatus: "failed", updatedAt: FieldValue.serverTimestamp()});
    throw new functions.https.HttpsError("failed-precondition", "Payment has not completed.");
  }
  await ref.update({
    paymentStatus: "paid",
    giftStatus: "submitted_for_review",
    status: "submitted_for_review",
    paidAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  return {paymentStatus: "paid", giftStatus: "submitted_for_review"};
});
