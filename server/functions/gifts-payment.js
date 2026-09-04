/* eslint-disable max-len, require-jsdoc */
const functions = require("firebase-functions/v1");
const crypto = require("node:crypto");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {getStorage} = require("firebase-admin/storage");
const giftVoiceMedia = require("./gift-voice-media");
const vanguardProtocol = require("./vanguard-protocol-core");
const {senderPaymentCallable} = require("./sender-app-check");
const {calculateWalletCheckout, normalizeEmail, roundMoney} = require("./wallet-core");
const {senderWalletProjectionRecord} = require("./roth-ledger-core");
const {giftPaymentMethodFromSplit} = require("./gifts-payment-core");

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

function text(value, fallback = "") {
  return String(value || fallback).trim();
}

function canonicalJson(value) {
  if (Array.isArray(value)) return value.map(canonicalJson);
  if (!value || typeof value !== "object") return value;
  if (typeof value.toMillis === "function") return value.toMillis();
  return Object.fromEntries(Object.keys(value).sort().map((key) => [key, canonicalJson(value[key])]));
}

function giftDraftFingerprint(payload) {
  return crypto.createHash("sha256").update(JSON.stringify(canonicalJson(payload))).digest("hex");
}

function clientGiftPayload(value) {
  const payload = cleanObject(value);
  const authorityFields = [
    "assignedAdminId", "adminDecision", "internalNotes", "paymentStatus", "giftStatus", "status",
    "paymentMethod", "applyRoth", "rothApplied", "cardAmount", "walletContributionGbp",
    "remainingStripeAmountGbp", "stripePaymentIntentId", "stripeCheckoutSessionId", "stripeCustomerId",
    "paymentKey", "paidAt", "dispatchEligible", "riderId", "assignedRiderId", "readyForCollection",
  ];
  for (const field of authorityFields) delete payload[field];
  return payload;
}

function authoritativeGiftBudget(value) {
  const amount = Number(value);
  if (!Number.isFinite(amount) || amount < 50 || amount > 1500 || !Number.isInteger(amount)) {
    throw new functions.https.HttpsError("failed-precondition", "Select a valid Gift budget.");
  }
  return amount;
}

async function giftWalletState(gift) {
  const db = getFirestore();
  const walletId = normalizeEmail(gift.senderEmail) || gift.senderId;
  const [walletSnap, projectionSnap] = await Promise.all([
    db.collection("wallets").doc(walletId).get(),
    db.collection("senderWallets").doc(gift.senderId).get(),
  ]);
  const wallet = walletSnap.exists ? walletSnap.data() || {} : {};
  const projection = projectionSnap.exists ? projectionSnap.data() || {} : {};
  const balances = [
    wallet.balance == null ? wallet.rothCredit : wallet.balance,
    projection.balance == null ? projection.rothCredit : projection.balance,
  ].map(Number).filter((value) => Number.isFinite(value) && value >= 0);
  return {
    walletId,
    frozen: wallet.isFrozen === true || projection.status === "frozen",
    balance: roundMoney(balances.length ? Math.max(...balances) : 0),
  };
}

async function ensureGiftStripeCustomer(stripe, gift) {
  const db = getFirestore();
  const userRef = db.collection("users").doc(gift.senderId);
  const userSnap = await userRef.get();
  const user = userSnap.exists ? userSnap.data() || {} : {};
  const existingId = text(user.stripeCustomerId || user.customerId);
  if (existingId) {
    try {
      const customer = await stripe.customers.retrieve(existingId);
      if (customer && !customer.deleted) return existingId;
    } catch (error) {
      if (text(error && (error.code || error.type || error.rawType)) !== "resource_missing") throw error;
    }
  }
  const customer = await stripe.customers.create({
    email: gift.senderEmail || undefined,
    name: gift.senderName || undefined,
    metadata: {userId: gift.senderId, source: "gift_payment"},
  });
  await userRef.set({
    stripeCustomerId: customer.id,
    customerId: customer.id,
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  return customer.id;
}

async function assertGiftPaymentMethodOwner(stripe, paymentMethodId, customerId) {
  if (!paymentMethodId) return;
  const method = await stripe.paymentMethods.retrieve(paymentMethodId);
  if (!method || text(method.customer) !== customerId) {
    throw new functions.https.HttpsError("permission-denied", "Saved payment method is unavailable.");
  }
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
  const participantPayload = cleanObject(data.campaignParticipant);
  const campaignId = text(participantPayload.campaignId);
  const campaignName = text(participantPayload.campaignName);
  const gross = authoritativeGiftBudget(
      data.grossGiftBudget || participantPayload.grossGiftBudget || participantPayload.budget || 0,
  );
  if (!campaignId || !campaignName) {
    throw new functions.https.HttpsError("invalid-argument", "Campaign details are required.");
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
  const payload = clientGiftPayload(data.giftDraft);
  const requestedId = text(data.giftDraftId || payload.giftDraftId).replace(/[/.#[\]]/g, "_");
  const draftRef = requestedId ?
    db.collection("giftPaymentDrafts").doc(requestedId) :
    db.collection("giftPaymentDrafts").doc();
  const gross = authoritativeGiftBudget(
      payload.grossGiftBudget || payload.grossBudget || payload.budget || 0,
  );
  if (!text(payload.recipientName) || !text(payload.deliveryAddress)) {
    throw new functions.https.HttpsError("invalid-argument", "Gift recipient and delivery details are required.");
  }
  const senderEmail = text(context.auth.token && context.auth.token.email) || text(payload.senderEmail);
  const draftFingerprint = giftDraftFingerprint({...payload, grossGiftBudget: gross});
  const quoteId = `gift_quote_${draftFingerprint.slice(0, 24)}`;
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
    authoritativeQuoteId: quoteId,
    draftFingerprint,
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
      if (existingData.draftFingerprint !== draftFingerprint) {
        throw new functions.https.HttpsError("failed-precondition", "Gift details changed. Start a fresh payment attempt.");
      }
      return;
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
  const persisted = await draftRef.get();
  return {giftDraftId: draftRef.id, gift: persisted.data() || draft};
}

exports.createGiftPayment = (stripe) => senderPaymentCallable(async (data, context) => {
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
  const gift = standardDraft ? standardDraft.gift : snap.data();
  const gross = roundMoney(gift.grossGiftBudget || gift.grossBudget || 0);
  if (gross < 50 || gift.paymentStatus === "paid") {
    throw new functions.https.HttpsError("failed-precondition", "Gift payment cannot be started.");
  }
  const wallet = data.applyRoth === true ? await giftWalletState(gift) : {
    walletId: normalizeEmail(gift.senderEmail) || gift.senderId,
    frozen: false,
    balance: 0,
  };
  const split = calculateWalletCheckout({
    orderTotalGbp: gross,
    walletBalanceGbp: data.applyRoth === true && !wallet.frozen ? wallet.balance : 0,
    selectedCurrency: "gbp",
  });
  const requestedMethod = giftPaymentMethodFromSplit(split, data.paymentMethod);
  const nativePayment = text(data.checkoutMode) === "payment_intent";
  const paymentKey = `gift_${giftDraftId}_${requestedMethod}_${split.stripeAmountMinor}`;
  const existingIntentId = text(gift.paymentKey) === paymentKey ?
    text(gift.stripePaymentIntentId) : "";
  await ref.set({
    paymentStatus: "payment_pending",
    paymentMethod: requestedMethod,
    walletContributionGbp: split.walletContributionGbp,
    remainingStripeAmountGbp: split.remainingGbp,
    rothApplied: split.walletContributionGbp,
    cardAmount: split.remainingGbp,
    paymentKey,
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});

  if (!split.stripeRequired) {
    const verifiedVoiceNote = await giftVoiceMedia.verifyGiftVoiceStorageObject({
      bucket: getStorage().bucket(),
      voiceNote: gift.voiceNote,
      senderId: gift.senderId,
    });
    return finalizeGiftPaymentAuthority({
      giftDraftId,
      actorUid: context.auth.uid,
      verifiedVoiceNote,
      payment: {
        provider: "roth",
        providerId: `roth_${giftDraftId}`,
        paymentIntentId: null,
        amountPence: 0,
        currency: "gbp",
        status: "succeeded",
        metadata: {giftDraftId, senderId: context.auth.uid},
      },
    });
  }

  if (nativePayment) {
    const customerId = await ensureGiftStripeCustomer(stripe, gift);
    const savedPaymentMethodId = text(data.paymentMethodId);
    if (savedPaymentMethodId) {
      await assertGiftPaymentMethodOwner(stripe, savedPaymentMethodId, customerId);
    }
    let intent;
    if (existingIntentId) {
      intent = await stripe.paymentIntents.retrieve(existingIntentId);
      const metadata = intent.metadata || {};
      if (text(intent.customer) !== customerId || metadata.giftDraftId !== giftDraftId ||
          metadata.senderId !== context.auth.uid) {
        throw new functions.https.HttpsError("permission-denied", "Gift payment ownership mismatch.");
      }
    } else {
      intent = await stripe.paymentIntents.create({
        amount: split.stripeAmountMinor,
        currency: "gbp",
        customer: customerId,
        automatic_payment_methods: {enabled: true},
        ...(savedPaymentMethodId ? {payment_method: savedPaymentMethodId} : {}),
        description: `Gifts by Circum for ${gift.recipientName || "recipient"}`,
        metadata: {
          type: "gift_payment_intent",
          giftDraftId,
          senderId: context.auth.uid,
          paymentMethod: requestedMethod,
          grossGiftBudget: `${gross}`,
          rothAppliedAmount: `${split.walletContributionGbp}`,
          remainingStripeAmountGbp: `${split.remainingGbp}`,
          paymentKey,
        },
      }, {idempotencyKey: paymentKey});
    }
    const ephemeralKey = await stripe.ephemeralKeys.create(
        {customer: customerId},
        {apiVersion: "2020-08-27"},
    );
    await ref.set({
      paymentStatus: "payment_pending",
      paymentMethod: requestedMethod,
      walletContributionGbp: split.walletContributionGbp,
      remainingStripeAmountGbp: split.remainingGbp,
      rothApplied: split.walletContributionGbp,
      cardAmount: split.remainingGbp,
      stripePaymentIntentId: intent.id,
      stripeCustomerId: customerId,
      paymentKey,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    return {
      giftDraftId,
      paymentIntentId: intent.id,
      clientSecret: intent.client_secret,
      customerId,
      ephemeralKeySecret: ephemeralKey.secret,
      amountDue: gross,
      rothAppliedAmount: split.walletContributionGbp,
      remainingAmount: split.remainingGbp,
      currency: "GBP",
      paymentMethod: requestedMethod,
      walletPaidInFull: false,
      requiresConfirmation: intent.status !== "succeeded",
    };
  }
  const baseUrl = "https://circumuk.com/?app=gifts";
  const successUrl = `${baseUrl}&gift_payment=success&giftDraftId=${giftDraftId}&session_id={CHECKOUT_SESSION_ID}`;
  const cancelUrl = `${baseUrl}&gift_payment=cancelled&giftDraftId=${giftDraftId}`;
  let session;
  try {
    session = await stripe.checkout.sessions.create({
      mode: "payment",
      customer_email: gift.senderEmail,
      line_items: [{
        quantity: 1,
        price_data: {
          currency: "gbp",
          unit_amount: split.stripeAmountMinor,
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
        paymentMethod: requestedMethod,
        grossGiftBudget: `${gross}`,
        rothAppliedAmount: `${split.walletContributionGbp}`,
        remainingStripeAmountGbp: `${split.remainingGbp}`,
      },
    });
  } catch (error) {
    console.error("createGiftPayment Stripe Checkout error", error);
    throw new functions.https.HttpsError("internal", "Could not start Stripe Checkout. Please try again.");
  }
  await ref.update({
    paymentStatus: "payment_pending",
    paymentMethod: requestedMethod,
    walletContributionGbp: split.walletContributionGbp,
    remainingStripeAmountGbp: split.remainingGbp,
    rothApplied: split.walletContributionGbp,
    cardAmount: split.remainingGbp,
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

async function finalizeGiftPaymentAuthority({
  giftDraftId,
  payment,
  actorUid = null,
  eventId = null,
  verifiedVoiceNote = undefined,
}) {
  const db = getFirestore();
  const draftRef = db.collection("giftPaymentDrafts").doc(giftDraftId);
  const giftRef = db.collection("giftRequests").doc(giftDraftId);
  if (!payment || payment.status !== "succeeded") {
    throw new functions.https.HttpsError("failed-precondition", "Payment has not completed.");
  }
  const preflightDraft = await draftRef.get();
  const checkedVoiceNote = verifiedVoiceNote !== undefined ? verifiedVoiceNote : preflightDraft.exists ?
    await giftVoiceMedia.verifyGiftVoiceStorageObject({
      bucket: getStorage().bucket(),
      voiceNote: preflightDraft.data() && preflightDraft.data().voiceNote,
      senderId: preflightDraft.data() && preflightDraft.data().senderId,
    }) :
    null;
  const preflightGift = preflightDraft.exists ? preflightDraft.data() || {} : {};
  const walletContribution = roundMoney(preflightGift.walletContributionGbp || 0);
  const walletId = normalizeEmail(preflightGift.senderEmail) || preflightGift.senderId;
  const walletRef = db.collection("wallets").doc(walletId || "missing");
  const senderWalletRef = db.collection("senderWallets").doc(preflightGift.senderId || "missing");
  const walletTransactionRef = db.collection("walletTransactions").doc(`gift_roth_${giftDraftId}`);
  return db.runTransaction(async (transaction) => {
    const reads = await Promise.all([
      transaction.get(draftRef),
      transaction.get(giftRef),
      ...(walletContribution > 0 ? [
        transaction.get(walletRef),
        transaction.get(senderWalletRef),
        transaction.get(walletTransactionRef),
      ] : []),
    ]);
    const [draftSnap, existingGiftSnap, walletSnap, senderWalletSnap, walletTransactionSnap] = reads;
    if (existingGiftSnap.exists) {
      const existing = existingGiftSnap.data() || {};
      if (existing.senderId === actorUid || !actorUid) {
        if (existing.paymentStatus === "paid") {
          return {paymentStatus: "paid", giftStatus: "submitted_for_review", giftRequestId: giftDraftId, idempotent: true};
        }
      }
      if (existing.paymentStatus === "paid") {
        throw new functions.https.HttpsError("permission-denied", "Gift request does not belong to this account.");
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
    const metadata = payment.metadata || {};
    if (metadata.giftDraftId !== giftDraftId || metadata.senderId !== gift.senderId) {
      throw new functions.https.HttpsError("permission-denied", "Gift payment ownership mismatch.");
    }
    if (payment.provider === "payment_intent" && payment.paymentIntentId !== gift.stripePaymentIntentId) {
      throw new functions.https.HttpsError("invalid-argument", "Invalid Gift PaymentIntent.");
    }
    if (payment.provider === "checkout" && payment.providerId !== gift.stripeCheckoutSessionId) {
      throw new functions.https.HttpsError("invalid-argument", "Invalid checkout session.");
    }
    const transactionVoiceNote = giftVoiceMedia.sanitizeGiftVoiceNoteMetadata(gift.voiceNote, gift.senderId);
    if ((transactionVoiceNote && !checkedVoiceNote) ||
        (checkedVoiceNote && (!transactionVoiceNote || transactionVoiceNote.storagePath !== checkedVoiceNote.storagePath))) {
      throw new functions.https.HttpsError("failed-precondition", "Gift voice note changed during checkout.");
    }
    const gross = roundMoney(gift.grossGiftBudget || gift.grossBudget || 0);
    const rothApplied = roundMoney(gift.walletContributionGbp || 0);
    const externalAmount = roundMoney(gift.remainingStripeAmountGbp == null ? gross : gift.remainingStripeAmountGbp);
    if (roundMoney(rothApplied + externalAmount) !== gross ||
        payment.currency !== "gbp" || Number(payment.amountPence || 0) !== Math.round(externalAmount * 100)) {
      throw new functions.https.HttpsError("failed-precondition", "Gift payment amount does not match the order.");
    }
    if (rothApplied > 0 && !(walletTransactionSnap && walletTransactionSnap.exists)) {
      const wallet = walletSnap && walletSnap.exists ? walletSnap.data() || {} : {};
      const senderWallet = senderWalletSnap && senderWalletSnap.exists ? senderWalletSnap.data() || {} : {};
      if (wallet.isFrozen === true || senderWallet.status === "frozen") {
        throw new functions.https.HttpsError("failed-precondition", "Roth is unavailable for this payment.");
      }
      const before = roundMoney(wallet.balance == null ? wallet.rothCredit : wallet.balance);
      if (before < rothApplied) {
        throw new functions.https.HttpsError("failed-precondition", "Roth balance changed. Please contact support.");
      }
      const after = roundMoney(before - rothApplied);
      const now = FieldValue.serverTimestamp();
      transaction.set(walletRef, {balance: after, rothCredit: after, updatedAt: now}, {merge: true});
      transaction.set(senderWalletRef, senderWalletProjectionRecord({
        userId: gift.senderId,
        balance: after,
        frozen: false,
        version: Number(senderWallet.version || 0) + 1,
        createdAt: senderWallet.createdAt || wallet.createdAt || now,
        updatedAt: now,
      }), {merge: true});
      transaction.set(walletTransactionRef, {
        transactionId: walletTransactionRef.id,
        id: walletTransactionRef.id,
        userId: walletId,
        uid: gift.senderId,
        walletId,
        type: "gift_payment_debit",
        amount: -rothApplied,
        direction: "debit",
        balanceType: "rothCredit",
        balanceBefore: before,
        balanceAfter: after,
        referenceId: giftDraftId,
        relatedEntityId: giftDraftId,
        idempotencyKey: walletTransactionRef.id,
        createdBy: "system",
        status: "completed",
        paymentProvider: payment.provider,
        createdAt: now,
      }, {merge: false});
    }
    transaction.set(giftRef, {
      ...gift,
      ...(checkedVoiceNote ? {voiceNote: checkedVoiceNote} : {}),
      paymentStatus: "paid",
      giftStatus: "submitted_for_review",
      status: "submitted_for_review",
      ...giftVanguardFields(),
      paymentMethod: giftPaymentMethodFromSplit({
        walletContributionGbp: rothApplied,
        remainingGbp: externalAmount,
      }, gift.paymentMethod),
      walletContributionGbp: rothApplied,
      remainingStripeAmountGbp: externalAmount,
      rothApplied,
      cardAmount: externalAmount,
      ...(payment.provider === "checkout" ? {stripeCheckoutSessionId: payment.providerId} : {}),
      stripePaymentIntentId: payment.paymentIntentId,
      stripePaymentEventId: eventId,
      paidAt: FieldValue.serverTimestamp(),
      createdAt: gift.createdAt || FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.set(db.collection("giftPaymentEvents").doc(eventId || `client_${payment.providerId}`), {
      eventId: eventId || null,
      giftDraftId,
      stripeCheckoutSessionId: payment.provider === "checkout" ? payment.providerId : null,
      stripePaymentIntentId: payment.paymentIntentId || null,
      paymentMethod: giftPaymentMethodFromSplit({
        walletContributionGbp: rothApplied,
        remainingGbp: externalAmount,
      }, gift.paymentMethod),
      grossGiftBudget: gross,
      rothAppliedAmount: rothApplied,
      remainingStripeAmountGbp: externalAmount,
      paymentStatus: "paid",
      source: eventId ? "stripe_webhook" : "client_recovery",
      createdAt: FieldValue.serverTimestamp(),
    }, {merge: false});
    if (checkedVoiceNote) {
      transaction.set(db.collection("giftVoiceMediaAudit").doc(), giftVoiceMedia.giftVoiceLifecycleAudit({
        action: "gift_voice_media_attached",
        actorUid: gift.senderId,
        giftDraftId,
        giftRequestId: giftDraftId,
        storagePath: checkedVoiceNote.storagePath,
        reason: eventId ? "stripe_webhook_finalization" : "client_payment_recovery",
      }), {merge: false});
    }
    transaction.delete(draftRef);
    return {paymentStatus: "paid", giftStatus: "submitted_for_review", giftRequestId: giftDraftId};
  });
}

async function finalizeGiftPaymentSession({giftDraftId, session, actorUid = null, eventId = null}) {
  return finalizeGiftPaymentAuthority({
    giftDraftId,
    actorUid,
    eventId,
    payment: {
      provider: "checkout",
      providerId: session && session.id,
      paymentIntentId: session && session.payment_intent,
      amountPence: Number(session && session.amount_total || 0),
      currency: text(session && session.currency).toLowerCase(),
      status: session && session.payment_status === "paid" ? "succeeded" : text(session && session.payment_status),
      metadata: session && session.metadata || {},
    },
  });
}

exports.finalizeGiftPayment = (stripe) => senderPaymentCallable(async (data, context) => {
  requireAuth(context);
  const giftDraftId = String(data.giftDraftId || "");
  const sessionId = String(data.sessionId || "");
  const paymentIntentId = String(data.paymentIntentId || "");
  const db = getFirestore();
  const snap = await db.collection("giftPaymentDrafts").doc(giftDraftId).get();
  const existing = await db.collection("giftRequests").doc(giftDraftId).get();
  if (!snap.exists && existing.exists && existing.data().senderId === context.auth.uid && existing.data().paymentStatus === "paid") {
    return {paymentStatus: "paid", giftStatus: "submitted_for_review", giftRequestId: giftDraftId};
  }
  if (!snap.exists || snap.data().senderId !== context.auth.uid) {
    throw new functions.https.HttpsError("not-found", "Gift draft not found.");
  }
  if (paymentIntentId) {
    if (paymentIntentId !== snap.data().stripePaymentIntentId) {
      throw new functions.https.HttpsError("invalid-argument", "Invalid Gift PaymentIntent.");
    }
    const intent = await stripe.paymentIntents.retrieve(paymentIntentId);
    return finalizeGiftPaymentAuthority({
      giftDraftId,
      actorUid: context.auth.uid,
      payment: {
        provider: "payment_intent",
        providerId: intent.id,
        paymentIntentId: intent.id,
        amountPence: Number(intent.amount_received || intent.amount || 0),
        currency: text(intent.currency).toLowerCase(),
        status: text(intent.status),
        metadata: intent.metadata || {},
      },
    });
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
exports.handleGiftPaymentIntent = async (stripe, intent, eventId = "") => {
  const metadata = intent && intent.metadata || {};
  if (metadata.type !== "gift_payment_intent") return {handled: false};
  if (text(intent.status) !== "succeeded") {
    await getFirestore().collection("giftPaymentDrafts").doc(text(metadata.giftDraftId)).set({
      paymentStatus: text(intent.status) || "payment_pending",
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    return {handled: true, paymentStatus: text(intent.status)};
  }
  const result = await finalizeGiftPaymentAuthority({
    giftDraftId: text(metadata.giftDraftId),
    eventId,
    payment: {
      provider: "payment_intent",
      providerId: intent.id,
      paymentIntentId: intent.id,
      amountPence: Number(intent.amount_received || intent.amount || 0),
      currency: text(intent.currency).toLowerCase(),
      status: text(intent.status),
      metadata,
    },
  });
  return {handled: true, ...result};
};
exports._private = {finalizeGiftPaymentAuthority};
exports.cleanupExpiredGiftVoiceDrafts = giftVoiceMedia.cleanupExpiredGiftVoiceDrafts;
exports.onGiftRequestVoiceMediaDeleted = giftVoiceMedia.onGiftRequestVoiceMediaDeleted;
