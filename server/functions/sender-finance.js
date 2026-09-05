/* eslint-disable max-len, require-jsdoc */
"use strict";

const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {senderPaymentCallable} = require("./sender-app-check");

function requireSender(context) {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in to manage payment methods.");
  }
  return {
    uid: context.auth.uid,
    email: context.auth.token.email || "",
    name: context.auth.token.name || "",
  };
}

async function ensureStripeCustomer({stripe, sender, db = getFirestore()}) {
  const userRef = db.collection("users").doc(sender.uid);
  const userSnap = await userRef.get();
  const user = userSnap.exists ? userSnap.data() : {};
  const existingCustomerId = user.stripeCustomerId || user.customerId;
  if (existingCustomerId) {
    try {
      const existingCustomer = await stripe.customers.retrieve(existingCustomerId);
      if (existingCustomer && existingCustomer.deleted !== true) return existingCustomerId;
    } catch (error) {
      if (error && error.code !== "resource_missing") throw error;
    }
  }
  const customer = await stripe.customers.create({
    email: sender.email || undefined,
    name: sender.name || undefined,
    metadata: {userId: sender.uid, source: "sender_mobile"},
  });
  await userRef.set({
    stripeCustomerId: customer.id,
    customerId: customer.id,
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  return customer.id;
}

function paymentMethodView(paymentMethod, defaultPaymentMethodId) {
  const card = paymentMethod.card || {};
  return {
    id: paymentMethod.id,
    type: paymentMethod.type,
    brand: card.brand || "",
    last4: card.last4 || "",
    expMonth: card.exp_month || null,
    expYear: card.exp_year || null,
    isDefault: paymentMethod.id === defaultPaymentMethodId,
  };
}

exports.listSenderPaymentMethods = (stripe) => senderPaymentCallable(async (_, context) => {
  const sender = requireSender(context);
  const customerId = await ensureStripeCustomer({stripe, sender});
  const customer = await stripe.customers.retrieve(customerId);
  const defaultPaymentMethodId =
    customer && customer.invoice_settings ? customer.invoice_settings.default_payment_method : null;
  const methods = await stripe.paymentMethods.list({
    customer: customerId,
    type: "card",
  });
  const prefs = await getFirestore()
      .collection("users")
      .doc(sender.uid)
      .collection("finance")
      .doc("checkoutPreferences")
      .get();
  const preference = prefs.exists ? prefs.data().preference || "ask_every_checkout" : "ask_every_checkout";
  return {
    customerId,
    defaultPaymentMethodId,
    preference,
    paymentMethods: methods.data.map((item) => paymentMethodView(item, defaultPaymentMethodId)),
    walletCompatible: true,
    applePaySupported: true,
    googlePaySupported: true,
  };
}, {secrets: ["STRIPE_SECRET_KEY"]});

exports.createSenderSetupIntent = (stripe) => senderPaymentCallable(async (_, context) => {
  const sender = requireSender(context);
  const customerId = await ensureStripeCustomer({stripe, sender});
  const ephemeralKey = await stripe.ephemeralKeys.create(
      {customer: customerId},
      {apiVersion: "2020-08-27"},
  );
  const setupIntent = await stripe.setupIntents.create({
    customer: customerId,
    usage: "off_session",
    payment_method_types: ["card"],
    metadata: {userId: sender.uid, source: "sender_mobile_wallet"},
  });
  return {
    customerId,
    ephemeralKeySecret: ephemeralKey.secret,
    setupIntentClientSecret: setupIntent.client_secret,
  };
}, {secrets: ["STRIPE_SECRET_KEY"]});

exports.detachSenderPaymentMethod = (stripe) => senderPaymentCallable(async (data, context) => {
  const sender = requireSender(context);
  const paymentMethodId = `${data && data.paymentMethodId || ""}`.trim();
  if (!paymentMethodId) {
    throw new functions.https.HttpsError("invalid-argument", "Payment method is required.");
  }
  const customerId = await ensureStripeCustomer({stripe, sender});
  const method = await stripe.paymentMethods.retrieve(paymentMethodId);
  if (method.customer !== customerId) {
    throw new functions.https.HttpsError("permission-denied", "Payment method does not belong to this Sender.");
  }
  const customer = await stripe.customers.retrieve(customerId);
  const isDefault = customer && customer.invoice_settings &&
    customer.invoice_settings.default_payment_method === paymentMethodId;
  await stripe.paymentMethods.detach(paymentMethodId);
  if (isDefault) {
    await stripe.customers.update(customerId, {
      invoice_settings: {default_payment_method: null},
    });
  }
  const db = getFirestore();
  if (isDefault) {
    await db.collection("users").doc(sender.uid).collection("finance")
        .doc("checkoutPreferences").set({
          defaultPaymentMethodId: FieldValue.delete(),
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
  }
  await db.collection("users").doc(sender.uid).collection("financeAudit").add({
    action: "payment_method_removed",
    paymentMethodId,
    createdAt: FieldValue.serverTimestamp(),
  });
  return {ok: true};
}, {secrets: ["STRIPE_SECRET_KEY"]});

exports.setDefaultSenderPaymentMethod = (stripe) => senderPaymentCallable(async (data, context) => {
  const sender = requireSender(context);
  const paymentMethodId = `${data && data.paymentMethodId || ""}`.trim();
  if (!paymentMethodId) {
    throw new functions.https.HttpsError("invalid-argument", "Payment method is required.");
  }
  const customerId = await ensureStripeCustomer({stripe, sender});
  const method = await stripe.paymentMethods.retrieve(paymentMethodId);
  if (method.customer !== customerId) {
    throw new functions.https.HttpsError("permission-denied", "Payment method does not belong to this Sender.");
  }
  await stripe.customers.update(customerId, {
    invoice_settings: {default_payment_method: paymentMethodId},
  });
  await getFirestore().collection("users").doc(sender.uid).collection("finance").doc("checkoutPreferences").set({
    defaultPaymentMethodId: paymentMethodId,
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  return {ok: true};
}, {secrets: ["STRIPE_SECRET_KEY"]});

exports.saveSenderCheckoutPreference = senderPaymentCallable(async (data, context) => {
  const sender = requireSender(context);
  const preference = `${data && data.preference || ""}`.trim();
  const allowed = new Set([
    "apple_pay_first",
    "google_pay_first",
    "default_card",
    "roth_first",
    "roth_then_card",
    "ask_every_checkout",
  ]);
  if (!allowed.has(preference)) {
    throw new functions.https.HttpsError("invalid-argument", "Unsupported checkout preference.");
  }
  await getFirestore().collection("users").doc(sender.uid).collection("finance").doc("checkoutPreferences").set({
    preference,
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  return {preference};
});

exports.ensureStripeCustomer = ensureStripeCustomer;
