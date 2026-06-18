/* eslint-disable max-len, require-jsdoc */
const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const rothLedger = require("./roth-ledger");
const {calculateWalletCheckout} = require("./wallet-core");

function requireAuth(context) {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in to continue with Gifts by Circum.");
  }
}

async function giftWalletBalanceForUser(db, context) {
  const email = `${context.auth.token.email || ""}`.trim().toLowerCase();
  const uid = context.auth.uid;
  const candidates = [email, uid].filter(Boolean);
  for (const id of candidates) {
    const snap = await db.collection("wallets").doc(id).get();
    if (snap.exists) {
      const wallet = snap.data() || {};
      return Number(wallet.balance == null ? wallet.rothCredit || 0 : wallet.balance);
    }
  }
  for (const [field, value] of [
    ["normalizedEmail", email],
    ["userEmail", email],
    ["email", email],
    ["uid", uid],
    ["userId", uid],
  ]) {
    if (!value) continue;
    const query = await db.collection("wallets").where(field, "==", value).limit(1).get();
    if (!query.empty) {
      const wallet = query.docs[0].data() || {};
      return Number(wallet.balance == null ? wallet.rothCredit || 0 : wallet.balance);
    }
  }
  return 0;
}

exports.createGiftPayment = (stripe) => functions.https.onCall(async (data, context) => {
  requireAuth(context);
  const db = getFirestore();
  const giftDraftId = String(data.giftDraftId || "");
  const ref = db.collection("giftPaymentDrafts").doc(giftDraftId);
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
  let split;
  if (gift.walletDeducted === true) {
    const storedWalletContribution = Number(gift.walletContributionGbp || 0);
    const storedRemaining = Number(gift.remainingStripeAmountGbp || Math.max(0, gross - storedWalletContribution));
    split = calculateWalletCheckout({
      orderTotalGbp: storedRemaining,
      walletBalanceGbp: 0,
      selectedCurrency: gift.paymentCurrency || data.paymentCurrency || "gbp",
    });
    split.orderTotalGbp = gross;
    split.walletContributionGbp = storedWalletContribution;
    split.remainingGbp = storedRemaining;
    split.stripeRequired = split.remainingGbp > 0;
  } else {
    const walletBalance = await giftWalletBalanceForUser(db, context);
    const selectedCurrency = gift.paymentCurrency || data.paymentCurrency || "gbp";
    split = calculateWalletCheckout({
      orderTotalGbp: gross,
      walletBalanceGbp: walletBalance,
      selectedCurrency,
    });
  }
  if (split.walletContributionGbp > 0 && gift.walletDeducted !== true && !split.stripeRequired) {
    await rothLedger.applyWalletDebit({
      userId: context.auth.uid,
      userEmail: context.auth.token.email,
      amount: split.walletContributionGbp,
      type: "gift_payment",
      referenceId: giftDraftId,
      notes: "Roth applied to Gifts by Circum experience.",
      transactionId: `wallet_gifts_${giftDraftId}`,
      metadata: {
        orderTotalGbp: split.orderTotalGbp,
        remainingGbp: split.remainingGbp,
        service: "gifts",
      },
    });
  }
  await ref.update({
    walletContributionGbp: split.walletContributionGbp,
    remainingStripeAmountGbp: split.remainingGbp,
    paymentCurrency: split.customerPaymentCurrency,
    estimatedCustomerPaymentAmount: split.customerPaymentAmount,
    walletDeducted: split.walletContributionGbp > 0 && !split.stripeRequired,
    updatedAt: FieldValue.serverTimestamp(),
  });
  if (!split.stripeRequired) {
    const giftRef = db.collection("giftRequests").doc(giftDraftId);
    await db.runTransaction(async (transaction) => {
      const latest = await transaction.get(ref);
      const existingGift = await transaction.get(giftRef);
      if (existingGift.exists) return;
      transaction.set(giftRef, {
        ...latest.data(),
        paymentStatus: "paid",
        giftStatus: "submitted_for_review",
        status: "submitted_for_review",
        stripeCheckoutSessionId: null,
        stripePaymentIntentId: null,
        walletPaidInFull: true,
        paymentMethod: "roth",
        giftStoryEnabled: true,
        giftStoryApproved: true,
        giftStoryShareEnabled: true,
        giftStoryCreatedAt: FieldValue.serverTimestamp(),
        giftStoryUpdatedAt: FieldValue.serverTimestamp(),
        paidAt: FieldValue.serverTimestamp(),
        createdAt: gift.createdAt || FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      transaction.delete(ref);
    });
    return {
      walletPaidInFull: true,
      paymentStatus: "paid",
      giftStatus: "submitted_for_review",
      giftRequestId: giftDraftId,
      walletContributionGbp: split.walletContributionGbp,
      remainingStripeAmountGbp: 0,
    };
  }
  const safeOccasion = `${gift.occasion || ""}`.trim().toLowerCase();
  const safeRecipient = `${gift.recipientName || ""}`.trim().split(/\s+/)[0];
  const giftDescription = safeOccasion && safeRecipient ?
    `Curated ${safeOccasion} gift experience for ${safeRecipient}` :
    "Gifts by Circum curated experience";
  let session;
  try {
    session = await stripe.checkout.sessions.create({
      mode: "payment",
      customer_email: gift.senderEmail,
      line_items: [{
        quantity: 1,
        price_data: {
          currency: split.customerPaymentCurrency,
          unit_amount: split.stripeAmountMinor,
          product_data: {
            name: "Gifts by Circum Experience",
            description: giftDescription,
          },
        },
      }],
      success_url: successUrl,
      cancel_url: cancelUrl,
      metadata: {
        giftDraftId,
        giftRequestId: giftDraftId,
        senderId: context.auth.uid,
        senderEmail: gift.senderEmail || context.auth.token.email || "",
        type: "gift_experience",
        paymentType: "gifts",
        totalBudget: `${split.orderTotalGbp}`,
        rothApplied: `${split.walletContributionGbp}`,
        stripeAmount: `${split.remainingGbp}`,
        occasion: gift.occasion || "",
        walletApplied: split.walletContributionGbp > 0 ? "true" : "false",
        orderTotalGbp: `${split.orderTotalGbp}`,
        walletContributionGbp: `${split.walletContributionGbp}`,
        remainingGbp: `${split.remainingGbp}`,
        customerPaymentCurrency: split.customerPaymentCurrency,
      },
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
  return {
    url: session.url,
    sessionId: session.id,
    orderTotalGbp: split.orderTotalGbp,
    walletContributionGbp: split.walletContributionGbp,
    remainingStripeAmountGbp: split.remainingGbp,
  };
});

exports.finalizeGiftPayment = (stripe) => functions.https.onCall(async (data, context) => {
  requireAuth(context);
  const giftDraftId = String(data.giftDraftId || "");
  const sessionId = String(data.sessionId || "");
  const db = getFirestore();
  const draftRef = db.collection("giftPaymentDrafts").doc(giftDraftId);
  const giftRef = db.collection("giftRequests").doc(giftDraftId);
  const snap = await draftRef.get();
  if (!snap.exists || snap.data().senderId !== context.auth.uid) {
    const existing = await giftRef.get();
    if (existing.exists && existing.data().senderId === context.auth.uid && existing.data().paymentStatus === "paid") {
      return {paymentStatus: "paid", giftStatus: "submitted_for_review", giftRequestId: giftDraftId};
    }
    throw new functions.https.HttpsError("not-found", "Gift draft not found.");
  }
  const gift = snap.data();
  const gross = Number(gift.grossGiftBudget || gift.grossBudget || 0);
  if (!sessionId || sessionId !== gift.stripeCheckoutSessionId) {
    throw new functions.https.HttpsError("invalid-argument", "Invalid checkout session.");
  }
  const session = await stripe.checkout.sessions.retrieve(sessionId);
  if (session.payment_status !== "paid") {
    throw new functions.https.HttpsError("failed-precondition", "Payment has not completed.");
  }
  const walletContribution = Number(gift.walletContributionGbp || 0);
  if (walletContribution > 0 && gift.walletDeducted !== true) {
    await rothLedger.applyWalletDebit({
      userId: context.auth.uid,
      userEmail: context.auth.token.email || gift.senderEmail,
      amount: walletContribution,
      type: "gift_payment",
      referenceId: giftDraftId,
      notes: "Roth applied to Gifts by Circum experience.",
      transactionId: `wallet_gifts_${giftDraftId}`,
      metadata: {
        orderTotalGbp: gross,
        remainingGbp: Number(gift.remainingStripeAmountGbp || 0),
        service: "gifts",
        stripeCheckoutSessionId: sessionId,
      },
    });
  }
  await db.runTransaction(async (transaction) => {
    transaction.set(giftRef, {
      ...gift,
      paymentStatus: "paid",
      giftStatus: "submitted_for_review",
      status: "submitted_for_review",
      stripeCheckoutSessionId: session.id,
      stripePaymentIntentId: session.payment_intent,
      walletDeducted: walletContribution > 0 || gift.walletDeducted === true,
      paymentMethod: walletContribution > 0 && Number(gift.remainingStripeAmountGbp || 0) <= 0 ? "roth" : "stripe",
      giftStoryEnabled: gift.giftStoryEnabled !== false,
      giftStoryApproved: gift.giftStoryApproved !== false,
      giftStoryShareEnabled: gift.giftStoryShareEnabled !== false,
      giftStoryCreatedAt: gift.giftStoryCreatedAt || FieldValue.serverTimestamp(),
      giftStoryUpdatedAt: FieldValue.serverTimestamp(),
      paidAt: FieldValue.serverTimestamp(),
      createdAt: gift.createdAt || FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.delete(draftRef);
  });
  await rothLedger.safeRecordRothMovement({
    db,
    userId: context.auth.uid,
    amount: gross,
    balanceType: rothLedger.BALANCE_TYPES.rothCredit,
    type: rothLedger.TRANSACTION_TYPES.stripePaymentRecord,
    reason: "Gifts by Circum Stripe payment recorded in Roth ledger.",
    relatedEntityId: giftDraftId,
    paymentProvider: "stripe",
    providerTransactionId: session.payment_intent || session.id,
    transactionId: `stripe_gift_${session.id}`,
    ledgerOnly: true,
    metadata: {
      giftRequestId: giftDraftId,
      service: "gifts",
      ledgerOnly: true,
      note: "Stripe remains execution partner; this records value movement only.",
    },
  });
  return {paymentStatus: "paid", giftStatus: "submitted_for_review", giftRequestId: giftDraftId};
});
