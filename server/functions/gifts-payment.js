/* eslint-disable max-len, require-jsdoc */
const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {getStorage} = require("firebase-admin/storage");
const giftVoiceMedia = require("./gift-voice-media");
const vanguardProtocol = require("./vanguard-protocol-core");
const {createGiftBudgetAuthority} = require("./gift-budget-authority");

function requireAuth(context) {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in to continue with Gifts by Circum.");
  }
}

function cleanObject(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  return Object.fromEntries(
      Object.entries(value).filter(([, entry]) => entry !== undefined),
  );
}

function withoutGiftDeliveryAuthority(value) {
  const clean = cleanObject(value);
  for (const key of [
    "deliveryCharge", "riderEarning", "riderPayout", "driverPayout",
    "platformShare", "riderSettlementAuthority", "giftDeliveryPricing",
    "authoritativeRouteFacts",
  ]) delete clean[key];
  return clean;
}

function text(value, fallback = "") {
  return String(value || fallback).trim();
}

function giftVanguardFields() {
  return {
    ...vanguardProtocol.initialProtocolFields({
      selected: true,
      required: true,
      irisRequired: true,
      irisRequiredReason: "Vanguard is required for Gifts deliveries.",
      category: "Gifts",
      description: "Gifts by Circum delivery",
    }),
    vanguardRequired: true,
    requiresVanguard: true,
    vanguardRequiredReason: "Vanguard is required for Gifts deliveries.",
  };
}

async function createCampaignPaymentDraft({data, context}) {
  const db = getFirestore();
  const participantPayload = withoutGiftDeliveryAuthority(data.campaignParticipant);
  const campaignId = text(participantPayload.campaignId);
  const campaignName = text(participantPayload.campaignName);
  const gross = Number(data.grossGiftBudget || participantPayload.grossGiftBudget || participantPayload.budget || 0);
  if (!campaignId || !campaignName) {
    throw new functions.https.HttpsError("invalid-argument", "Campaign details are required.");
  }
  if (gross < 50) {
    throw new functions.https.HttpsError("failed-precondition", "Campaign gift budget is below the minimum.");
  }
  const participantRef = db.collection("giftCampaignParticipants").doc();
  const draftRef = db.collection("giftPaymentDrafts").doc();
  const senderEmail = text(context.auth.token && context.auth.token.email);
  const now = FieldValue.serverTimestamp();
  const participant = {
    ...participantPayload,
    userId: context.auth.uid,
    senderId: context.auth.uid,
    email: senderEmail || text(participantPayload.email),
    campaignParticipantId: participantRef.id,
    paymentDraftId: draftRef.id,
    source: "sender_mobile_campaign",
    status: "checkout_pending",
    campaignStatus: "checkout_pending",
    paymentStatus: "checkout_pending",
    paymentMethod: text(data.paymentMethod || participantPayload.paymentMethod, "card"),
    giftCampaignTotal: gross,
    grossGiftBudget: gross,
    updatedAt: now,
    createdAt: now,
  };
  const draft = {
    ...participant,
    giftDraftId: draftRef.id,
    senderId: context.auth.uid,
    senderEmail: senderEmail || text(participantPayload.email),
    campaignFlow: "anonymous",
    giftStatus: "campaign_participation",
    selectedBudgetGbp: gross,
    grossBudget: gross,
    grossGiftBudget: gross,
    applyRoth: data.applyRoth === true,
    returnOrigin: text(data.returnOrigin),
  };
  await db.runTransaction(async (transaction) => {
    transaction.set(participantRef, participant, {merge: false});
    transaction.set(draftRef, draft, {merge: false});
    transaction.set(db.collection("giftCampaignParticipantEvents").doc(), {
      participantId: participantRef.id,
      giftDraftId: draftRef.id,
      campaignId,
      actorUid: context.auth.uid,
      action: "sender_campaign_participation_requested",
      source: "createGiftPayment",
      createdAt: now,
    }, {merge: false});
  });
  return {giftDraftId: draftRef.id, participantId: participantRef.id, gift: draft};
}

async function createStandardPaymentDraft({data, context}) {
  const db = getFirestore();
  const payload = withoutGiftDeliveryAuthority(data.giftDraft);
  const requestedId = text(data.giftDraftId || payload.giftDraftId).replace(/[/.#[\]]/g, "_");
  const draftRef = requestedId ?
    db.collection("giftPaymentDrafts").doc(requestedId) :
    db.collection("giftPaymentDrafts").doc();
  const gross = Number(payload.grossGiftBudget || payload.grossBudget || payload.budget || 0);
  if (gross < 50) {
    throw new functions.https.HttpsError("failed-precondition", "Gift payment cannot be started.");
  }
  if (!text(payload.recipientName) || !text(payload.deliveryAddress)) {
    throw new functions.https.HttpsError("invalid-argument", "Gift recipient and delivery details are required.");
  }
  const senderEmail = text(context.auth.token && context.auth.token.email) || text(payload.senderEmail);
  const now = FieldValue.serverTimestamp();
  const draft = {
    ...payload,
    giftDraftId: draftRef.id,
    senderId: context.auth.uid,
    senderEmail,
    grossGiftBudget: gross,
    grossBudget: gross,
    budget: gross,
    paymentStatus: "payment_pending",
    giftStatus: text(payload.giftStatus || "draft"),
    status: text(payload.status || "draft"),
    source: "createGiftPayment",
    createdAt: now,
    updatedAt: now,
  };
  await db.runTransaction(async (transaction) => {
    const existing = await transaction.get(draftRef);
    if (existing.exists) {
      const existingData = existing.data() || {};
      if (existingData.senderId !== context.auth.uid || existingData.paymentStatus === "paid") {
        throw new functions.https.HttpsError("failed-precondition", "Gift payment cannot be started.");
      }
    }
    transaction.set(draftRef, draft, {merge: false});
    transaction.set(db.collection("giftPaymentEvents").doc(), {
      giftDraftId: draftRef.id,
      actorUid: context.auth.uid,
      action: "gift_payment_draft_created",
      source: "createGiftPayment",
      createdAt: now,
    }, {merge: false});
  });
  return {giftDraftId: draftRef.id, gift: draft};
}

exports.createGiftPayment = (stripe) => functions.runWith({enforceAppCheck: true}).https.onCall(async (data, context) => {
  requireAuth(context);
  const campaignRequest = data.source === "sender_mobile_campaign" && data.campaignParticipant;
  const campaignDraft = campaignRequest ?
    await createCampaignPaymentDraft({data, context}) :
    null;
  const standardDraft = !campaignDraft && data.giftDraft ?
    await createStandardPaymentDraft({data, context}) :
    null;
  const giftDraftId = String(
      (standardDraft && standardDraft.giftDraftId) ||
      (campaignDraft && campaignDraft.giftDraftId) ||
      data.giftDraftId ||
      "",
  );
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
      metadata: {
        giftDraftId,
        senderId: context.auth.uid,
        type: "gift_experience",
        productType: "gift",
        productId: giftDraftId,
        giftRequestId: giftDraftId,
        canonicalTransactionId: giftDraftId,
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
  if (campaignDraft && campaignDraft.participantId) {
    await getFirestore().collection("giftCampaignParticipants").doc(campaignDraft.participantId).set({
      paymentStatus: "checkout_pending",
      stripeCheckoutSessionId: session.id,
      paymentDraftId: giftDraftId,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  }
  return {
    url: session.url,
    sessionId: session.id,
    giftDraftId,
    campaignParticipantId: campaignDraft ? campaignDraft.participantId : data.campaignParticipantId,
  };
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
  const preflightDraft = await draftRef.get();
  const verifiedVoiceNote = preflightDraft.exists ?
    await giftVoiceMedia.verifyGiftVoiceStorageObject({
      bucket: getStorage().bucket(),
      voiceNote: preflightDraft.data() && preflightDraft.data().voiceNote,
      senderId: preflightDraft.data() && preflightDraft.data().senderId,
    }) :
    null;
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
    const transactionVoiceNote = giftVoiceMedia.sanitizeGiftVoiceNoteMetadata(gift.voiceNote, gift.senderId);
    if ((transactionVoiceNote && !verifiedVoiceNote) ||
        (verifiedVoiceNote && (!transactionVoiceNote || transactionVoiceNote.storagePath !== verifiedVoiceNote.storagePath))) {
      throw new functions.https.HttpsError("failed-precondition", "Gift voice note changed during checkout.");
    }
    const gross = Number(gift.grossGiftBudget || gift.grossBudget || 0);
    const expectedAmount = Math.round(gross * 100);
    if (session.currency !== "gbp" || Number(session.amount_total || 0) !== expectedAmount) {
      throw new functions.https.HttpsError("failed-precondition", "Gift payment amount does not match the order.");
    }
    const budgetAuthority = createGiftBudgetAuthority(expectedAmount);
    transaction.set(giftRef, {
      ...gift,
      ...(verifiedVoiceNote ? {voiceNote: verifiedVoiceNote} : {}),
      paymentStatus: "paid",
      giftStatus: "submitted_for_review",
      status: "submitted_for_review",
      ...giftVanguardFields(),
      stripeCheckoutSessionId: session.id,
      stripePaymentIntentId: session.payment_intent,
      stripePaymentEventId: eventId,
      productType: "gift",
      productId: giftDraftId,
      giftRequestId: giftDraftId,
      paymentId: session.id,
      canonicalTransactionId: session.id,
      totalAmount: gross,
      rothApplied: 0,
      stripeAmount: gross,
      paidAt: FieldValue.serverTimestamp(),
      createdAt: gift.createdAt || FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      giftBudgetAuthority: budgetAuthority,
    });
    transaction.set(db.collection("giftPaymentEvents").doc(eventId || `client_${session.id}`), {
      eventId: eventId || null,
      giftDraftId,
      productType: "gift",
      productId: giftDraftId,
      giftRequestId: giftDraftId,
      paymentId: session.id,
      canonicalTransactionId: session.id,
      totalAmount: gross,
      rothApplied: 0,
      stripeAmount: gross,
      stripeCheckoutSessionId: session.id,
      stripePaymentIntentId: session.payment_intent || null,
      paymentStatus: "paid",
      source: eventId ? "stripe_webhook" : "client_recovery",
      createdAt: FieldValue.serverTimestamp(),
    }, {merge: false});
    if (verifiedVoiceNote) {
      transaction.set(db.collection("giftVoiceMediaAudit").doc(), giftVoiceMedia.giftVoiceLifecycleAudit({
        action: "gift_voice_media_attached",
        actorUid: gift.senderId,
        giftDraftId,
        giftRequestId: giftDraftId,
        storagePath: verifiedVoiceNote.storagePath,
        reason: eventId ? "stripe_webhook_finalization" : "client_payment_recovery",
      }), {merge: false});
    }
    transaction.delete(draftRef);
    return {paymentStatus: "paid", giftStatus: "submitted_for_review", giftRequestId: giftDraftId};
  });
}

exports.finalizeGiftPayment = (stripe) => functions.runWith({enforceAppCheck: true}).https.onCall(async (data, context) => {
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
exports.cleanupExpiredGiftVoiceDrafts = giftVoiceMedia.cleanupExpiredGiftVoiceDrafts;
exports.onGiftRequestVoiceMediaDeleted = giftVoiceMedia.onGiftRequestVoiceMediaDeleted;
