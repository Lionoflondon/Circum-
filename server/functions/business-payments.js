/* eslint-disable max-len */
"use strict";

const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");

function money(value) {
  const parsed = Number(value || 0);
  if (!Number.isFinite(parsed)) return 0;
  return Math.round(parsed * 100) / 100;
}

function isMember(account, context) {
  const uid = context.auth && context.auth.uid;
  const email = `${context.auth && context.auth.token && context.auth.token.email || ""}`.toLowerCase();
  const members = Array.isArray(account.teamMemberIds) ? account.teamMemberIds.map((item) => `${item}`.toLowerCase()) : [];
  return account.createdByUserId === uid || members.includes(`${uid}`.toLowerCase()) || (email && members.includes(email));
}

async function requireBusinessMember(businessId, context) {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in to continue.");
  }
  const snap = await getFirestore().collection("businessAccounts").doc(businessId).get();
  if (!snap.exists) {
    throw new functions.https.HttpsError("not-found", "Business account not found.");
  }
  const account = snap.data() || {};
  if (!isMember(account, context)) {
    throw new functions.https.HttpsError("permission-denied", "You do not have access to this Business account.");
  }
  return {id: snap.id, ...account};
}

async function creditBusinessRoth({businessId, amount, type, note, metadata = {}}) {
  const db = getFirestore();
  const walletRef = db.collection("business_wallets").doc(businessId);
  const txRef = metadata.transactionId ?
    walletRef.collection("transactions").doc(metadata.transactionId) :
    walletRef.collection("transactions").doc();
  const accountRef = db.collection("businessAccounts").doc(businessId);
  await db.runTransaction(async (transaction) => {
    const walletSnap = await transaction.get(walletRef);
    const previous = money(walletSnap.data() && walletSnap.data().balance);
    const resulting = money(previous + amount);
    transaction.set(walletRef, {
      businessId,
      balance: resulting,
      availableBalance: resulting,
      pendingBalance: 0,
      lifetimeReceived: FieldValue.increment(amount),
      status: walletSnap.data() && walletSnap.data().status || "active",
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    transaction.set(txRef, {
      transactionId: txRef.id,
      businessId,
      direction: "credit",
      amount,
      type,
      note,
      createdAt: FieldValue.serverTimestamp(),
      previousBalance: previous,
      resultingBalance: resulting,
      paymentProvider: metadata.paymentProvider || "stripe",
      metadata,
    });
    transaction.set(accountRef, {
      businessRothBalance: resulting,
      rothBalance: resulting,
      recentBusinessRothTransactions: FieldValue.arrayUnion({
        transactionId: txRef.id,
        direction: "credit",
        amount,
        source: type,
        reason: note,
        createdAt: new Date(),
      }),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  });
}

async function debitBusinessRoth({businessId, amount, invoiceId, metadata = {}}) {
  const db = getFirestore();
  const walletRef = db.collection("business_wallets").doc(businessId);
  const txRef = walletRef.collection("transactions").doc(`invoice_roth_${invoiceId}_${metadata.paymentId || Date.now()}`);
  const accountRef = db.collection("businessAccounts").doc(businessId);
  return db.runTransaction(async (transaction) => {
    const existingTx = await transaction.get(txRef);
    if (existingTx.exists) return false;
    const walletSnap = await transaction.get(walletRef);
    const previous = money(walletSnap.data() && walletSnap.data().balance);
    const resulting = money(previous - amount);
    if (resulting < 0) {
      throw new functions.https.HttpsError("failed-precondition", "Business Roth balance is too low.");
    }
    transaction.set(walletRef, {
      businessId,
      balance: resulting,
      availableBalance: resulting,
      lifetimeSpent: FieldValue.increment(amount),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    transaction.set(txRef, {
      transactionId: txRef.id,
      businessId,
      direction: "debit",
      amount,
      type: "invoice_payment",
      method: "roth",
      invoiceId,
      note: "Business invoice paid with Roth.",
      createdAt: FieldValue.serverTimestamp(),
      previousBalance: previous,
      resultingBalance: resulting,
      metadata,
    });
    transaction.set(accountRef, {
      businessRothBalance: resulting,
      rothBalance: resulting,
      recentBusinessRothTransactions: FieldValue.arrayUnion({
        transactionId: txRef.id,
        direction: "debit",
        amount,
        source: "invoice_payment",
        reason: "Business invoice paid with Roth.",
        invoiceId,
        createdAt: new Date(),
      }),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    return true;
  });
}

async function markInvoicePaid({invoiceId, businessId, amount, method, stripeSessionId = null, stripePaymentIntentId = null, rothAmount = 0, paymentId = null}) {
  const db = getFirestore();
  const invoiceRef = db.collection("businessInvoices").doc(invoiceId);
  const paymentRef = db.collection("businessInvoicePayments").doc(paymentId || stripeSessionId || `roth_${invoiceId}`);
  await db.runTransaction(async (transaction) => {
    const invoiceSnap = await transaction.get(invoiceRef);
    if (!invoiceSnap.exists) return;
    const invoice = invoiceSnap.data() || {};
    if (`${invoice.status || ""}` === "paid" || `${invoice.status || ""}` === "paid_manually") return;
    const total = money(invoice.total || invoice.subtotal || invoice.balanceDue || amount + rothAmount);
    const previousPaid = money(invoice.amountPaid);
    const paymentTotal = money(amount + rothAmount);
    const nextPaid = money(Math.min(total, previousPaid + paymentTotal));
    const nextBalance = money(Math.max(0, total - nextPaid));
    const nextStatus = nextBalance <= 0 ? "paid" : "partially_paid";
    transaction.set(invoiceRef, {
      status: nextStatus,
      amountPaid: nextPaid,
      balanceDue: nextBalance,
      paymentMethod: method,
      stripeCheckoutSessionId: stripeSessionId,
      stripePaymentIntentId,
      ...(nextStatus === "paid" ? {paidAt: FieldValue.serverTimestamp()} : {}),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    transaction.set(paymentRef, {
      paymentId: paymentRef.id,
      businessId,
      invoiceId,
      amount,
      rothAmount,
      method,
      status: "paid",
      stripeCheckoutSessionId: stripeSessionId,
      stripePaymentIntentId,
      paidAt: FieldValue.serverTimestamp(),
      createdAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    transaction.set(db.collection("businessAccounts").doc(businessId), {
      recentBusinessInvoices: FieldValue.arrayUnion({
        invoiceId,
        invoiceNumber: invoice.invoiceNumber,
        status: nextStatus,
        total,
        amountPaid: nextPaid,
        balanceDue: nextBalance,
        paymentMethod: method,
        updatedAt: new Date(),
        ...(nextStatus === "paid" ? {paidAt: new Date()} : {}),
      }),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    transaction.set(db.collection("adminAuditLogs").doc(), {
      action: nextStatus === "paid" ? "business_invoice_paid" : "business_invoice_part_payment",
      actionType: nextStatus === "paid" ? "business_invoice_paid" : "business_invoice_part_payment",
      businessId,
      invoiceId,
      amount: paymentTotal,
      paymentMethod: method,
      previousStatus: invoice.status || null,
      newStatus: nextStatus,
      balanceDue: nextBalance,
      stripeCheckoutSessionId: stripeSessionId,
      createdAt: FieldValue.serverTimestamp(),
    });
  });
}

exports.createBusinessRothCheckout = (stripe) => functions.https.onCall(async (data, context) => {
  const businessId = `${data.businessId || ""}`.trim();
  const amount = money(data.amount);
  if (!businessId || amount < 1) {
    throw new functions.https.HttpsError("invalid-argument", "Choose a valid Business account and Roth amount.");
  }
  const account = await requireBusinessMember(businessId, context);
  const db = getFirestore();
  const purchaseRef = db.collection("businessRothPurchases").doc();
  const baseUrl = `${data.returnUrl || "https://circumuk.com/?app=business&section=invoicing"}`;
  const separator = baseUrl.includes("?") ? "&" : "?";
  const session = await stripe.checkout.sessions.create({
    mode: "payment",
    payment_method_types: ["card"],
    line_items: [{
      quantity: 1,
      price_data: {
        currency: "gbp",
        unit_amount: Math.round(amount * 100),
        product_data: {
          name: "Circum Business Roth",
          description: "Internal Circum credit. Roth is not withdrawable cash.",
        },
      },
    }],
    success_url: `${baseUrl}${separator}roth_purchase=success&purchaseId=${purchaseRef.id}&session_id={CHECKOUT_SESSION_ID}`,
    cancel_url: `${baseUrl}${separator}roth_purchase=cancelled&purchaseId=${purchaseRef.id}`,
    metadata: {
      type: "business_roth_purchase",
      businessId,
      purchaseRequestId: purchaseRef.id,
      amountGbp: `${amount}`,
      createdByUserId: context.auth.uid,
    },
  });
  await purchaseRef.set({
    purchaseId: purchaseRef.id,
    businessId,
    businessName: account.businessName || "Business",
    amountGbp: amount,
    amountRoth: amount,
    rothAmount: amount,
    paymentMethod: "card",
    paymentProvider: "stripe",
    stripeSessionId: session.id,
    status: "pending_verification",
    createdAt: FieldValue.serverTimestamp(),
    paidAt: null,
    creditedAt: null,
    createdByUserId: context.auth.uid,
  });
  await db.collection("businessAccounts").doc(businessId).set({
    recentBusinessRothPurchases: FieldValue.arrayUnion({
      purchaseId: purchaseRef.id,
      amountGbp: amount,
      rothAmount: amount,
      status: "pending_verification",
      paymentProvider: "stripe",
      createdAt: new Date(),
    }),
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  return {checkoutUrl: session.url, sessionId: session.id, purchaseId: purchaseRef.id};
});

exports.createBusinessInvoiceCheckout = (stripe) => functions.https.onCall(async (data, context) => {
  const businessId = `${data.businessId || ""}`.trim();
  const invoiceId = `${data.invoiceId || ""}`.trim();
  const rothAmount = money(data.rothAmount);
  if (!businessId || !invoiceId) {
    throw new functions.https.HttpsError("invalid-argument", "Choose a valid Business invoice.");
  }
  await requireBusinessMember(businessId, context);
  const db = getFirestore();
  const invoiceSnap = await db.collection("businessInvoices").doc(invoiceId).get();
  if (!invoiceSnap.exists) {
    throw new functions.https.HttpsError("not-found", "Business invoice not found.");
  }
  const invoice = invoiceSnap.data() || {};
  const balanceDue = money(invoice.balanceDue || invoice.total || 0);
  const paymentAmount = money(data.paymentAmount || balanceDue);
  if (balanceDue <= 0) {
    throw new functions.https.HttpsError("failed-precondition", "This invoice is already paid.");
  }
  if (paymentAmount <= 0 || paymentAmount > balanceDue) {
    throw new functions.https.HttpsError("invalid-argument", "Payment amount must be greater than zero and no more than the invoice balance.");
  }
  if (rothAmount > paymentAmount) {
    throw new functions.https.HttpsError("invalid-argument", "Roth cannot exceed the selected payment amount.");
  }
  const cardAmount = money(paymentAmount - rothAmount);
  if (cardAmount <= 0) {
    const paymentId = `roth_${invoiceId}_${Math.round(paymentAmount * 100)}`;
    const debited = await debitBusinessRoth({businessId, amount: rothAmount, invoiceId, metadata: {paymentId}});
    if (!debited) return {paid: true, method: "roth", paymentAmount, duplicate: true};
    await markInvoicePaid({invoiceId, businessId, amount: 0, rothAmount, method: "roth", paymentId});
    return {paid: true, method: "roth", paymentAmount};
  }
  const paymentRef = db.collection("businessInvoicePayments").doc();
  const baseUrl = `${data.returnUrl || "https://circumuk.com/?app=business&section=invoicing"}`;
  const separator = baseUrl.includes("?") ? "&" : "?";
  const bookingId = `${invoice.bookingId || invoice.deliveryId || invoice.requestId || ""}`;
  const session = await stripe.checkout.sessions.create({
    mode: "payment",
    payment_method_types: ["card"],
    line_items: [{
      quantity: 1,
      price_data: {
        currency: "gbp",
        unit_amount: Math.round(cardAmount * 100),
        product_data: {
          name: `${invoice.invoiceNumber || "Circum Business invoice"}`,
          description: "Business invoice payment.",
        },
      },
    }],
    success_url: `${baseUrl}${separator}paymentStatus=payment-success&invoiceId=${invoiceId}&businessId=${businessId}&paymentId=${paymentRef.id}&checkoutSessionId={CHECKOUT_SESSION_ID}`,
    cancel_url: `${baseUrl}${separator}paymentStatus=payment-cancelled&invoiceId=${invoiceId}&businessId=${businessId}&paymentId=${paymentRef.id}`,
    metadata: {
      type: "business_invoice_payment",
      businessId,
      invoiceId,
      bookingId,
      paymentId: paymentRef.id,
      cardAmountGbp: `${cardAmount}`,
      rothAmountGbp: `${rothAmount}`,
      paymentAmountGbp: `${paymentAmount}`,
      returnUrl: baseUrl,
      paymentStatus: "pending_verification",
      createdByUserId: context.auth.uid,
    },
  });
  await paymentRef.set({
    paymentId: paymentRef.id,
    businessId,
    invoiceId,
    bookingId,
    amount: cardAmount,
    rothAmount,
    method: rothAmount > 0 ? "roth_card" : "card",
    status: "pending_verification",
    paymentStatus: "pending_verification",
    stripeSessionId: session.id,
    checkoutSessionId: session.id,
    paymentIntentId: session.payment_intent || null,
    returnUrl: baseUrl,
    createdAt: FieldValue.serverTimestamp(),
    createdByUserId: context.auth.uid,
  });
  return {checkoutUrl: session.url, sessionId: session.id, paymentId: paymentRef.id};
});

exports.handleBusinessCheckoutSession = async (sessionData, eventId = null) => {
  const metadata = sessionData.metadata || {};
  if (metadata.type === "business_roth_purchase") {
    const businessId = metadata.businessId;
    const purchaseId = metadata.purchaseRequestId;
    const amount = money(metadata.amountGbp || Number(sessionData.amount_total || 0) / 100);
    const purchaseRef = getFirestore().collection("businessRothPurchases").doc(purchaseId);
    const snap = await purchaseRef.get();
    const purchase = snap.exists ? snap.data() || {} : {};
    if (purchase.status === "paid" || purchase.creditedAt) return;
    await creditBusinessRoth({
      businessId,
      amount,
      type: "roth_purchase",
      note: "Business Roth card purchase verified by Stripe.",
      metadata: {
        transactionId: `business_roth_purchase_${sessionData.id}`,
        paymentProvider: "stripe",
        stripeEventId: eventId,
        stripeCheckoutSessionId: sessionData.id,
        stripePaymentIntentId: sessionData.payment_intent || null,
        purchaseId,
      },
    });
    await purchaseRef.set({
      status: "paid",
      paidAt: FieldValue.serverTimestamp(),
      creditedAt: FieldValue.serverTimestamp(),
      stripePaymentIntentId: sessionData.payment_intent || null,
      stripeSessionId: sessionData.id,
    }, {merge: true});
  }
  if (metadata.type === "business_invoice_payment") {
    const businessId = metadata.businessId;
    const invoiceId = metadata.invoiceId;
    const paymentId = metadata.paymentId || sessionData.id;
    const paymentSnap = await getFirestore().collection("businessInvoicePayments").doc(paymentId).get();
    if (paymentSnap.exists && paymentSnap.data() && paymentSnap.data().status === "paid") return;
    const rothAmount = money(metadata.rothAmountGbp);
    const cardAmount = money(metadata.cardAmountGbp || Number(sessionData.amount_total || 0) / 100);
    if (rothAmount > 0) {
      await debitBusinessRoth({businessId, amount: rothAmount, invoiceId, metadata: {paymentId, stripeCheckoutSessionId: sessionData.id}});
    }
    await markInvoicePaid({
      invoiceId,
      businessId,
      amount: cardAmount,
      rothAmount,
      method: rothAmount > 0 ? "roth_card" : "card",
      stripeSessionId: sessionData.id,
      stripePaymentIntentId: sessionData.payment_intent || null,
      paymentId,
    });
  }
};
