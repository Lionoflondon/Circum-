/* eslint-disable max-len */
"use strict";

const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue, GeoPoint} = require("firebase-admin/firestore");
const {calculateWalletCheckout, roundMoney, minorUnits} = require("./wallet-core");
const rothLedger = require("./roth-ledger");
const vanguardProtocol = require("./vanguard-protocol-core");

const BASE_FARE_GBP = 5;
const ADDITIONAL_FARE_PER_MILE_GBP = 1.5;
const SHORT_TRIP_FARE_FLOOR_MILES = 1.6;
const LONG_DISTANCE_THRESHOLD_MILES = 20;
const LONG_DISTANCE_MULTIPLIER = 1.2;
const VANGUARD_ADD_ON_GBP = 1.99;

function requireSender(context) {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in to continue booking.");
  }
  return {
    uid: context.auth.uid,
    email: context.auth.token.email || "",
    name: context.auth.token.name || "",
  };
}

function text(value) {
  return `${value || ""}`.trim();
}

function money(value) {
  return roundMoney(Number(value || 0));
}

function speedKey(value) {
  const normalized = text(value).toLowerCase();
  if (normalized === "economy") return "economy";
  if (normalized === "express") return "express";
  return "standard";
}

function weightSurcharge(weightKg) {
  const weight = Math.max(0, Number(weightKg || 0));
  if (weight > 40) return 25;
  if (weight > 20) return 15;
  if (weight > 10) return 7;
  if (weight > 5) return 3;
  return 0;
}

function distanceFare(distanceMiles) {
  const distance = Math.max(0, Number(distanceMiles || 0));
  if (distance < SHORT_TRIP_FARE_FLOOR_MILES) return 0;
  const multiplier = distance > LONG_DISTANCE_THRESHOLD_MILES ? LONG_DISTANCE_MULTIPLIER : 1;
  return money(distance * ADDITIONAL_FARE_PER_MILE_GBP * multiplier);
}

function speedAdjustment(subtotal, speed) {
  if (speed === "economy") return -1.5;
  if (speed === "express") return Math.max(2.99, money(subtotal * 0.2));
  return 0;
}

function quotePayload(data, uid) {
  const selectedSpeed = speedKey(data.selectedSpeed || data.selectedOption);
  const weightKg = Math.max(0.5, Number(data.weightKg || data.parcel && data.parcel.weightKg || 0.5));
  const base = BASE_FARE_GBP;
  const distance = distanceFare(data.distanceMiles);
  const weight = weightSurcharge(weightKg);
  const subtotal = money(base + distance + weight);
  const speed = money(speedAdjustment(subtotal, selectedSpeed));
  const vanguardSelected = data.vanguardProtocolEnabled === true || data.vanguard === true;
  const vanguardRequired = data.iris && data.iris.vanguardRequired === true;
  const vanguard = vanguardSelected || vanguardRequired ? VANGUARD_ADD_ON_GBP : 0;
  const total = money(Math.max(0, subtotal + speed + vanguard));
  const quoteId = text(data.quoteId) || `sender_quote_${uid}_${Date.now()}`;
  return {
    quoteId,
    userId: uid,
    currency: "GBP",
    selectedSpeed,
    weightKg,
    vanguardProtocolEnabled: vanguard > 0,
    vanguardRequired,
    vanguardRequiredReason: data.iris && data.iris.vanguardRequiredReason || "",
    lineItems: [
      {key: "base_delivery", label: "Base delivery", amount: base},
      {key: "distance", label: "Distance", amount: distance},
      {key: "weight", label: "Parcel weight", amount: weight},
      {key: "speed_adjustment", label: `${selectedSpeed[0].toUpperCase()}${selectedSpeed.slice(1)} priority`, amount: speed},
      ...(vanguard > 0 ? [{key: "vanguard", label: "Vanguard Protection", amount: vanguard}] : []),
    ],
    total,
    finalAmount: total,
    amountDue: total,
    pricingSource: "sender_backend_quote_v1",
  };
}

async function walletBalanceForSender(sender) {
  const walletId = (sender.email || sender.uid).trim().toLowerCase();
  const snap = await getFirestore().collection("wallets").doc(walletId).get();
  const wallet = snap.exists ? snap.data() : {};
  return money(wallet.balance == null ? wallet.rothCredit : wallet.balance);
}

async function stripeCustomerForSender(sender) {
  const db = getFirestore();
  const userRef = db.collection("users").doc(sender.uid);
  const userSnap = await userRef.get();
  const user = userSnap.exists ? userSnap.data() : {};
  return user.stripeCustomerId || user.customerId || null;
}

exports.getSenderRothBalance = functions.https.onCall(async (_, context) => {
  const sender = requireSender(context);
  const balance = await walletBalanceForSender(sender);
  return {
    balance,
    availableRoth: balance,
    currency: "ROTH",
    source: "canonical_backend_wallet",
  };
});

exports.createSenderBookingQuote = functions.https.onCall(async (data, context) => {
  const sender = requireSender(context);
  const quote = quotePayload(data || {}, sender.uid);
  await getFirestore().collection("senderBookingQuotes").doc(quote.quoteId).set({
    ...quote,
    createdAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  return quote;
});

exports.createSenderPaymentSession = (stripe) => functions.https.onCall(async (data, context) => {
  const sender = requireSender(context);
  const quoteId = text(data.quoteId);
  if (!quoteId) {
    throw new functions.https.HttpsError("invalid-argument", "A backend quote is required before payment.");
  }
  const db = getFirestore();
  const quoteSnap = await db.collection("senderBookingQuotes").doc(quoteId).get();
  if (!quoteSnap.exists || quoteSnap.data().userId !== sender.uid) {
    throw new functions.https.HttpsError("not-found", "Booking quote not found.");
  }
  const quote = quoteSnap.data();
  const total = money(quote.total || quote.finalAmount || quote.amountDue);
  const rothEnabled = data.rothEnabled === true;
  const rothBalance = rothEnabled ? await walletBalanceForSender(sender) : 0;
  const savedPaymentMethodId = text(data.paymentMethodId);
  const requestedFallback = text(data.fallbackMethod) || "card";
  const split = calculateWalletCheckout({
    orderTotalGbp: total,
    walletBalanceGbp: rothEnabled ? rothBalance : 0,
    selectedCurrency: "gbp",
  });
  const sessionRef = db.collection("senderPaymentSessions").doc();
  const sessionBase = {
    paymentSessionId: sessionRef.id,
    quoteId,
    userId: sender.uid,
    userEmail: sender.email,
    amountDue: total,
    rothEnabled,
    rothAppliedAmount: split.walletContributionGbp,
    remainingAmount: split.remainingGbp,
    currency: "GBP",
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
  if (!split.stripeRequired) {
    await rothLedger.applyWalletDebit({
      userId: sender.uid,
      userEmail: sender.email,
      amount: split.walletContributionGbp,
      type: "delivery_payment",
      referenceId: sessionRef.id,
      notes: "Roth applied to Circum delivery payment.",
      transactionId: `wallet_delivery_${sessionRef.id}`,
      metadata: {quoteId, service: "delivery", source: "sender_booking_payment"},
    });
    await sessionRef.set({
      ...sessionBase,
      status: "succeeded",
      paymentStatus: "succeeded",
      paymentMethod: "roth",
      confirmedAt: FieldValue.serverTimestamp(),
    });
    return {
      ...sessionBase,
      status: "succeeded",
      paymentStatus: "succeeded",
      paymentMethod: "roth",
    };
  }
  const customerId = savedPaymentMethodId ? await stripeCustomerForSender(sender) : null;
  if (savedPaymentMethodId && !customerId) {
    throw new functions.https.HttpsError("failed-precondition", "Saved payment method is unavailable.");
  }
  if (savedPaymentMethodId) {
    const method = await stripe.paymentMethods.retrieve(savedPaymentMethodId);
    if (method.customer !== customerId) {
      throw new functions.https.HttpsError("permission-denied", "Saved payment method does not belong to this Sender.");
    }
  }
  const intent = await stripe.paymentIntents.create({
    amount: minorUnits(split.customerPaymentAmount, "gbp"),
    currency: "gbp",
    payment_method_types: ["card"],
    customer: customerId || undefined,
    payment_method: savedPaymentMethodId || undefined,
    setup_future_usage: savedPaymentMethodId ? undefined : "off_session",
    metadata: {
      paymentType: "delivery",
      userId: sender.uid,
      userEmail: sender.email,
      quoteId,
      paymentSessionId: sessionRef.id,
      rothAppliedAmount: `${split.walletContributionGbp}`,
      remainingAmount: `${split.remainingGbp}`,
      fallbackMethod: requestedFallback,
      savedPaymentMethodId,
    },
  });
  await sessionRef.set({
    ...sessionBase,
    status: intent.status,
    paymentStatus: intent.status,
    paymentMethod: requestedFallback,
    savedPaymentMethodId: savedPaymentMethodId || null,
    stripePaymentIntentId: intent.id,
    clientSecret: intent.client_secret,
  });
  return {
    ...sessionBase,
    status: intent.status,
    paymentStatus: intent.status,
    paymentMethod: requestedFallback,
    savedPaymentMethodId: savedPaymentMethodId || null,
    stripePaymentIntentId: intent.id,
    clientSecret: intent.client_secret,
  };
});

function geoData(point = {}) {
  const lat = Number(point.lat || point.latitude || 0);
  const lng = Number(point.lng || point.longitude || 0);
  return {
    geopoint: new GeoPoint(lat, lng),
    geohash: "",
  };
}

exports.createSenderPaidDelivery = (stripe) => functions.https.onCall(async (data, context) => {
  const sender = requireSender(context);
  const quoteId = text(data.quoteId);
  const paymentSessionId = text(data.paymentSessionId);
  if (!quoteId || !paymentSessionId) {
    throw new functions.https.HttpsError("invalid-argument", "Confirmed payment and quote are required.");
  }
  const db = getFirestore();
  const [quoteSnap, paymentSnap] = await Promise.all([
    db.collection("senderBookingQuotes").doc(quoteId).get(),
    db.collection("senderPaymentSessions").doc(paymentSessionId).get(),
  ]);
  if (!quoteSnap.exists || quoteSnap.data().userId !== sender.uid) {
    throw new functions.https.HttpsError("not-found", "Booking quote not found.");
  }
  if (!paymentSnap.exists || paymentSnap.data().userId !== sender.uid) {
    throw new functions.https.HttpsError("not-found", "Payment session not found.");
  }
  let payment = paymentSnap.data();
  if (`${payment.paymentStatus || payment.status}` !== "succeeded" && payment.stripePaymentIntentId) {
    const intent = await stripe.paymentIntents.retrieve(payment.stripePaymentIntentId);
    if (intent.status === "succeeded") {
      await paymentSnap.ref.update({
        status: "succeeded",
        paymentStatus: "succeeded",
        confirmedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      payment = {...payment, status: "succeeded", paymentStatus: "succeeded"};
    }
  }
  if (`${payment.paymentStatus || payment.status}` !== "succeeded") {
    throw new functions.https.HttpsError("failed-precondition", "Stripe payment must be confirmed before delivery creation.");
  }
  const quote = quoteSnap.data();
  const requestId = text(data.requestId) || `sender_${Date.now()}_${sender.uid}`;
  const deliveryRef = db.collection("deliveryRequests").doc(requestId);
  const existing = await deliveryRef.get();
  if (existing.exists) return {requestId, deliveryId: deliveryRef.id, idempotent: true};
  const pickup = data.pickup || {};
  const dropoff = data.dropoff || {};
  const parcel = data.parcel || {};
  const iris = data.iris || {};
  const vanguardFields = vanguardProtocol.initialProtocolFields({
    selected: quote.vanguardProtocolEnabled === true,
    required: quote.vanguardRequired === true,
    irisRequired: quote.vanguardRequired === true,
    irisRequiredReason: quote.vanguardRequiredReason,
    itemName: parcel.itemName,
    description: parcel.description,
    category: iris.category,
  });
  await deliveryRef.set({
    requestId,
    role: "user",
    userId: sender.uid,
    senderId: sender.uid,
    senderName: sender.name,
    senderEmail: sender.email,
    pickupDetails: {
      fullname: pickup.fullname || sender.name || "Sender",
      phone: pickup.phone || "",
      position: geoData(pickup.coordinates),
      moreInformation: pickup.instructions || "",
      locality: pickup.locality || "",
      address: pickup.address || "",
      subAddress: pickup.subAddress || "",
    },
    dropoffDetails: {
      fullname: dropoff.fullname || data.recipient && data.recipient.name || "",
      phone: dropoff.phone || data.recipient && data.recipient.phone || "",
      position: geoData(dropoff.coordinates),
      moreInformation: dropoff.instructions || data.recipient && data.recipient.deliveryNotes || "",
      locality: dropoff.locality || "",
      address: dropoff.address || "",
      subAddress: dropoff.subAddress || "",
    },
    pickupPosition: geoData(pickup.coordinates),
    pickupLocality: pickup.locality || "",
    recipient: data.recipient || {},
    deliveryTime: data.deliveryTime || {},
    parcel,
    iris,
    selectedSpeed: quote.selectedSpeed,
    quoteId,
    paymentSessionId,
    price: quote.total,
    paidAmount: quote.total,
    paymentStatus: "paid",
    paymentMethod: payment.paymentMethod,
    rothAppliedAmount: payment.rothAppliedAmount || 0,
    remainingAmount: payment.remainingAmount || 0,
    pricingBreakdown: quote,
    currency: "GBP",
    status: "requested",
    ...vanguardFields,
    dispatchProtocol: {
      vanguard: vanguardFields.vanguardProtocolEnabled === true,
    },
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  return {requestId, deliveryId: deliveryRef.id};
});
