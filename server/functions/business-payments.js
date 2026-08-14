/* eslint-disable max-len, require-jsdoc */
"use strict";

const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {
  verifiedStripePaidGbpSession,
  verifiedStripeRothPurchase,
} = require("./roth-ledger-core");
const {requireAdmin} = require("./admin-auth");
const {calculateWalletCheckout} = require("./wallet-core");
const communicationEngine = require("./communication-engine");
const {businessAuthority} = require("./business-authority");

function money(value) {
  const parsed = Number(value || 0);
  if (!Number.isFinite(parsed)) return 0;
  return Math.round(parsed * 100) / 100;
}

function text(value, max = 500) {
  return `${value || ""}`.trim().slice(0, max);
}

function invoiceNumberFor(ref) {
  const today = new Date().toISOString().slice(0, 10).replace(/-/g, "");
  return `CIR-BIZ-${today}-${ref.id.slice(0, 6).toUpperCase()}`;
}

function normaliseLineItems(items, fallbackDescription, total) {
  const lines = Array.isArray(items) ? items : [];
  const normalised = lines.slice(0, 20).map((item) => ({
    description: text(item && item.description, 160),
    amount: money(item && item.amount),
  })).filter((item) => item.description && item.amount > 0);
  if (normalised.length) return normalised;
  return [{
    description: text(fallbackDescription, 160) || "Business services",
    amount: total,
  }];
}

async function requireBusinessMember(businessId, context, {financial = false} = {}) {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in to continue.");
  }
  const snap = await getFirestore().collection("businessAccounts").doc(businessId).get();
  if (!snap.exists) {
    throw new functions.https.HttpsError("not-found", "Business account not found.");
  }
  const account = snap.data() || {};
  const authority = businessAuthority(account, {
    uid: context.auth.uid,
    email: context.auth.token && context.auth.token.email,
  });
  if (!authority.member || financial && !authority.financialAuthorized) {
    throw new functions.https.HttpsError("permission-denied", "You do not have access to this Business account.");
  }
  return {id: snap.id, ...account, authority};
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
    const existingTx = await transaction.get(txRef);
    if (existingTx.exists) return;
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
      amountGBP: metadata.amountGBP == null ? amount : metadata.amountGBP,
      rothIssued: metadata.rothIssued == null ? amount : metadata.rothIssued,
      currency: metadata.currency || "GBP",
      source: metadata.source || "purchase",
      paymentIntentId: metadata.stripePaymentIntentId || null,
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

async function payBusinessInvoiceAtomically({
  businessId,
  invoiceId,
  cardAmount = 0,
  rothAmount = 0,
  method,
  stripeSessionId = null,
  stripePaymentIntentId = null,
  paymentId = null,
  metadata = {},
}) {
  const db = getFirestore();
  const paymentRef = db.collection("businessInvoicePayments")
      .doc(paymentId || stripeSessionId || `roth_${invoiceId}`);
  const invoiceRef = db.collection("businessInvoices").doc(invoiceId);
  const walletRef = db.collection("business_wallets").doc(businessId);
  const accountRef = db.collection("businessAccounts").doc(businessId);
  const walletTxRef = walletRef.collection("transactions")
      .doc(`invoice_roth_${invoiceId}_${paymentRef.id}`);
  return db.runTransaction(async (transaction) => {
    const reads = [
      transaction.get(paymentRef),
      transaction.get(invoiceRef),
    ];
    if (money(rothAmount) > 0) {
      reads.push(transaction.get(walletRef));
      reads.push(transaction.get(walletTxRef));
    }
    const [existingPaymentSnap, invoiceSnap, walletSnap, existingWalletTxSnap] =
      await Promise.all(reads);
    if (existingPaymentSnap.exists &&
        `${existingPaymentSnap.data().status || ""}` === "paid") {
      return {
        paid: true,
        duplicate: true,
        paymentId: paymentRef.id,
        invoiceId,
      };
    }
    if (!invoiceSnap.exists) {
      throw new functions.https.HttpsError("not-found", "Business invoice not found.");
    }
    const invoice = invoiceSnap.data() || {};
    if (`${invoice.status || ""}` === "paid" ||
        `${invoice.status || ""}` === "paid_manually") {
      transaction.set(paymentRef, {
        paymentId: paymentRef.id,
        businessId,
        invoiceId,
        amount: money(cardAmount),
        rothAmount: money(rothAmount),
        method,
        status: "paid",
        duplicateOfPaidInvoice: true,
        stripeCheckoutSessionId: stripeSessionId,
        stripePaymentIntentId,
        paidAt: FieldValue.serverTimestamp(),
        createdAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      return {
        paid: true,
        duplicate: true,
        paymentId: paymentRef.id,
        invoiceId,
      };
    }
    const normalizedCardAmount = money(cardAmount);
    const normalizedRothAmount = money(rothAmount);
    const total = money(invoice.total || invoice.subtotal || invoice.balanceDue ||
      normalizedCardAmount + normalizedRothAmount);
    const previousPaid = money(invoice.amountPaid);
    const paymentTotal = money(normalizedCardAmount + normalizedRothAmount);
    const nextPaid = money(Math.min(total, previousPaid + paymentTotal));
    const nextBalance = money(Math.max(0, total - nextPaid));
    const nextStatus = nextBalance <= 0 ? "paid" : "partially_paid";
    let previousWalletBalance = null;
    let resultingWalletBalance = null;
    if (normalizedRothAmount > 0) {
      if (existingWalletTxSnap && existingWalletTxSnap.exists) {
        throw new functions.https.HttpsError(
            "already-exists",
            "This Business Roth payment is already being processed.",
        );
      }
      const wallet = walletSnap && walletSnap.exists ? walletSnap.data() || {} : {};
      previousWalletBalance = money(wallet.balance || wallet.availableBalance);
      resultingWalletBalance = money(previousWalletBalance - normalizedRothAmount);
      if (resultingWalletBalance < 0) {
        throw new functions.https.HttpsError("failed-precondition", "Business Roth balance is too low.");
      }
      transaction.set(walletRef, {
        businessId,
        balance: resultingWalletBalance,
        availableBalance: resultingWalletBalance,
        lifetimeSpent: FieldValue.increment(normalizedRothAmount),
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      transaction.set(walletTxRef, {
        transactionId: walletTxRef.id,
        businessId,
        direction: "debit",
        amount: normalizedRothAmount,
        type: "invoice_payment",
        method: "roth",
        invoiceId,
        paymentId: paymentRef.id,
        note: "Business invoice paid with Roth.",
        createdAt: FieldValue.serverTimestamp(),
        previousBalance: previousWalletBalance,
        resultingBalance: resultingWalletBalance,
        metadata: {
          ...metadata,
          productType: "business",
          productId: invoiceId,
          businessId,
          invoiceId,
          paymentId: paymentRef.id,
          canonicalTransactionId: paymentRef.id,
          totalAmount: total,
          rothApplied: normalizedRothAmount,
          stripeAmount: normalizedCardAmount,
        },
      }, {merge: false});
    }
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
      amount: normalizedCardAmount,
      rothAmount: normalizedRothAmount,
      method,
      status: "paid",
      stripeCheckoutSessionId: stripeSessionId,
      stripePaymentIntentId,
      paidAt: FieldValue.serverTimestamp(),
      createdAt: FieldValue.serverTimestamp(),
      metadata: {
        ...metadata,
        productType: "business",
        productId: invoiceId,
        businessId,
        invoiceId,
        paymentId: paymentRef.id,
        canonicalTransactionId: paymentRef.id,
        totalAmount: total,
        rothApplied: normalizedRothAmount,
        stripeAmount: normalizedCardAmount,
      },
    }, {merge: true});
    transaction.set(accountRef, {
      ...(normalizedRothAmount > 0 ? {
        businessRothBalance: resultingWalletBalance,
        rothBalance: resultingWalletBalance,
      } : {}),
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
    return {
      paid: true,
      duplicate: false,
      paymentId: paymentRef.id,
      invoiceId,
      status: nextStatus,
      balanceDue: nextBalance,
      rothBalance: resultingWalletBalance,
    };
  });
}

exports.adminCreateBusinessInvoice = functions.runWith({enforceAppCheck: true}).https.onCall(async (payload, context) => {
  const adminUid = requireAdmin(context, "Your Admin role cannot create Business invoices.");
  const data = payload || {};
  const db = getFirestore();
  const businessId = text(data.businessId, 120);
  const total = money(data.total || data.amount || data.balanceDue);
  const reason = text(data.reason, 500);
  if (!businessId || total <= 0) {
    throw new functions.https.HttpsError("invalid-argument", "Choose a Business account and invoice amount.");
  }
  if (!reason) {
    throw new functions.https.HttpsError("invalid-argument", "Add a reason before creating the invoice.");
  }
  const businessRef = db.collection("businessAccounts").doc(businessId);
  const businessSnap = await businessRef.get();
  if (!businessSnap.exists) {
    throw new functions.https.HttpsError("not-found", "Business account not found.");
  }
  const business = businessSnap.data() || {};
  const invoiceRef = db.collection("businessInvoices").doc();
  const invoiceNumber = text(data.invoiceNumber, 80) || invoiceNumberFor(invoiceRef);
  const lineItems = normaliseLineItems(data.lineItems, data.description, total);
  const subtotal = money(lineItems.reduce((sum, item) => sum + item.amount, 0));
  const invoiceTotal = money(total || subtotal);
  const now = FieldValue.serverTimestamp();
  const dueDate = text(data.dueDate, 40) || null;
  const invoice = {
    invoiceId: invoiceRef.id,
    invoiceNumber,
    businessId,
    businessName: business.businessName || business.companyName || "Business",
    billingEmail: business.billingEmail || business.contactEmail || business.ownerEmail || null,
    description: text(data.description, 500),
    lineItems,
    subtotal: invoiceTotal,
    total: invoiceTotal,
    amountPaid: 0,
    balanceDue: invoiceTotal,
    currency: "GBP",
    status: "open",
    invoiceStatus: "open",
    paymentStatus: "unpaid",
    source: "circum_operations",
    createdByAdminId: adminUid,
    createdByAdminEmail: text(context.auth.token && context.auth.token.email, 160),
    createdReason: reason,
    deliveryIds: Array.isArray(data.deliveryIds) ? data.deliveryIds.map((item) => text(item, 120)).filter(Boolean).slice(0, 50) : [],
    dueDate,
    createdAt: now,
    updatedAt: now,
  };
  await db.runTransaction(async (transaction) => {
    transaction.set(invoiceRef, invoice);
    transaction.set(businessRef, {
      outstandingInvoiceAmount: FieldValue.increment(invoiceTotal),
      updatedAt: now,
    }, {merge: true});
    const auditPayload = {
      action: "business_invoice_created",
      actionType: "business_invoice_created",
      actorId: adminUid,
      actorEmail: text(context.auth.token && context.auth.token.email, 160),
      businessId,
      invoiceId: invoiceRef.id,
      invoiceNumber,
      amount: invoiceTotal,
      reason,
      createdAt: now,
    };
    transaction.set(db.collection("businessAuditLogs").doc(), auditPayload);
    transaction.set(db.collection("adminAuditLogs").doc(), {
      ...auditPayload,
      recordType: "businessInvoices",
      recordId: invoiceRef.id,
    });
  });
  return {
    invoiceId: invoiceRef.id,
    invoiceNumber,
    businessId,
    total: invoiceTotal,
    balanceDue: invoiceTotal,
    status: "open",
  };
});

exports.createBusinessRothCheckout = (stripe) => functions.runWith({enforceAppCheck: true}).https.onCall(async (data, context) => {
  const businessId = `${data.businessId || ""}`.trim();
  const amount = money(data.amount);
  if (!businessId || amount < 1) {
    throw new functions.https.HttpsError("invalid-argument", "Choose a valid Business account and Roth amount.");
  }
  const account = await requireBusinessMember(businessId, context, {financial: true});
  const db = getFirestore();
  const purchaseRef = db.collection("businessRothPurchases").doc();
  const baseUrl = `${data.returnUrl || "https://circumuk.com/?app=business&section=invoicing"}`;
  const separator = baseUrl.includes("?") ? "&" : "?";
  const session = await stripe.checkout.sessions.create({
    mode: "payment",
    payment_method_types: ["card"],
    client_reference_id: businessId,
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
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  return {checkoutUrl: session.url, sessionId: session.id, purchaseId: purchaseRef.id};
});

exports.createBusinessInvoiceCheckout = (stripe) => functions.runWith({enforceAppCheck: true}).https.onCall(async (data, context) => {
  const businessId = `${data.businessId || ""}`.trim();
  const invoiceId = `${data.invoiceId || ""}`.trim();
  if (!businessId || !invoiceId) {
    throw new functions.https.HttpsError("invalid-argument", "Choose a valid Business invoice.");
  }
  await requireBusinessMember(businessId, context, {financial: true});
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
  const useRoth = data.useRoth === true;
  const walletSnap = await db.collection("business_wallets").doc(businessId).get();
  const wallet = walletSnap.exists ? walletSnap.data() || {} : {};
  const walletBalance = useRoth && `${wallet.status || "active"}` === "active" ? money(wallet.balance || wallet.availableBalance) : 0;
  const split = calculateWalletCheckout({
    orderTotalGbp: paymentAmount,
    walletBalanceGbp: walletBalance,
    selectedCurrency: "gbp",
  });
  const rothAmount = split.walletContributionGbp;
  const cardAmount = split.remainingGbp;
  const requestedMethod = ["apple_pay", "google_pay", "saved_card", "card"].includes(`${data.paymentMethod || ""}`) ? `${data.paymentMethod}` : "card";
  if (cardAmount <= 0) {
    const paymentId = `roth_${invoiceId}_${Math.round(paymentAmount * 100)}`;
    const result = await payBusinessInvoiceAtomically({
      businessId,
      invoiceId,
      cardAmount: 0,
      rothAmount,
      method: "roth",
      paymentId,
      metadata: {paymentId, source: "business_invoice_roth_only"},
    });
    return {paid: true, method: "roth", paymentAmount, totalInvoice: balanceDue, rothApplied: rothAmount, cardAmount: 0, duplicate: result.duplicate === true};
  }
  const paymentRef = db.collection("businessInvoicePayments").doc();
  const baseUrl = `${data.returnUrl || "https://circumuk.com/?app=business&section=invoicing"}`;
  const separator = baseUrl.includes("?") ? "&" : "?";
  const bookingId = `${invoice.bookingId || invoice.deliveryId || invoice.requestId || ""}`;
  const session = await stripe.checkout.sessions.create({
    mode: "payment",
    payment_method_types: ["card"],
    client_reference_id: businessId,
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
      requestedPaymentMethod: requestedMethod,
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
    totalInvoice: balanceDue,
    cardAmount,
    method: rothAmount > 0 ? `roth_${requestedMethod}` : requestedMethod,
    requestedPaymentMethod: requestedMethod,
    status: "pending_verification",
    paymentStatus: "pending_verification",
    stripeSessionId: session.id,
    checkoutSessionId: session.id,
    paymentIntentId: session.payment_intent || null,
    returnUrl: baseUrl,
    createdAt: FieldValue.serverTimestamp(),
    createdByUserId: context.auth.uid,
  });
  return {checkoutUrl: session.url, sessionId: session.id, paymentId: paymentRef.id, paid: false, method: rothAmount > 0 ? `roth_${requestedMethod}` : requestedMethod, paymentAmount, totalInvoice: balanceDue, rothApplied: rothAmount, cardAmount};
});

exports.handleBusinessCheckoutSession = async (sessionData, eventId = null) => {
  const metadata = sessionData.metadata || {};
  if (metadata.type === "business_roth_purchase") {
    const businessId = metadata.businessId;
    const purchaseId = metadata.purchaseRequestId;
    if (!businessId || !purchaseId) {
      throw new Error("Business Roth purchase owner could not be verified.");
    }
    let verifiedPurchase;
    try {
      verifiedPurchase = verifiedStripeRothPurchase(sessionData, {ownerId: businessId});
    } catch (error) {
      await getFirestore().collection("businessRothPurchases").doc(purchaseId).set({
        status: "failed",
        failureCode: "payment_not_verified",
        failureMessage: error && error.message ? error.message : "Business Roth payment could not be verified.",
        stripePaymentIntentId: sessionData.payment_intent || null,
        stripeSessionId: sessionData.id || null,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      if (metadata.createdByUserId) {
        try {
          await communicationEngine.emitNotification({
            recipientId: metadata.createdByUserId,
            recipientRole: "sender",
            type: "business_roth_purchase_failed",
            title: "Business Roth purchase needs attention",
            body: "We could not add Roth from this payment. No Business Roth has been credited.",
            data: {
              correlationId: `business_roth_purchase_${sessionData.id || eventId || "unknown"}`,
              businessId,
              purchaseId,
              stripeEventId: eventId || "",
              stripeCheckoutSessionId: sessionData.id || "",
              paymentIntentId: sessionData.payment_intent || "",
              failureCode: "payment_not_verified",
            },
          });
        } catch (notificationError) {
          console.error("Business Roth purchase failure notification failed", {
            businessId,
            purchaseId,
            error: notificationError && notificationError.message ? notificationError.message : notificationError,
          });
        }
      }
      throw error;
    }
    const amount = verifiedPurchase.rothIssued;
    const purchaseRef = getFirestore().collection("businessRothPurchases").doc(purchaseId);
    const snap = await purchaseRef.get();
    const purchaseRecord = snap.exists ? snap.data() || {} : {};
    if (purchaseRecord.status === "paid" || purchaseRecord.creditedAt) return;
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
        amountGBP: verifiedPurchase.amountGBP,
        rothIssued: verifiedPurchase.rothIssued,
        currency: verifiedPurchase.currency,
        source: "purchase",
        purchaseId,
      },
    });
    await purchaseRef.set({
      status: "paid",
      paidAt: FieldValue.serverTimestamp(),
      creditedAt: FieldValue.serverTimestamp(),
      stripePaymentIntentId: sessionData.payment_intent || null,
      stripeSessionId: sessionData.id,
      amountGBP: verifiedPurchase.amountGBP,
      amountRoth: verifiedPurchase.rothIssued,
      rothAmount: verifiedPurchase.rothIssued,
      currency: verifiedPurchase.currency,
    }, {merge: true});
    if (metadata.createdByUserId) {
      try {
        await communicationEngine.emitNotification({
          recipientId: metadata.createdByUserId,
          recipientRole: "sender",
          type: "business_roth_purchase_completed",
          title: "Business Roth added",
          body: `${amount} Roth has been added to your Business balance.`,
          data: {
            correlationId: `business_roth_purchase_${sessionData.id}`,
            businessId,
            purchaseId,
            paymentIntentId: sessionData.payment_intent || "",
            amountGBP: `${verifiedPurchase.amountGBP}`,
            rothIssued: `${verifiedPurchase.rothIssued}`,
          },
        });
      } catch (error) {
        console.error("Business Roth purchase notification failed", {
          businessId,
          purchaseId,
          error: error && error.message ? error.message : error,
        });
      }
    }
  }
  if (metadata.type === "business_invoice_payment") {
    const businessId = metadata.businessId;
    const invoiceId = metadata.invoiceId;
    const paymentId = metadata.paymentId || sessionData.id;
    const paymentSnap = await getFirestore().collection("businessInvoicePayments").doc(paymentId).get();
    if (!paymentSnap.exists) {
      throw new Error("Business invoice payment record is missing.");
    }
    const payment = paymentSnap.data() || {};
    if (payment.status === "paid") return;
    const rothAmount = money(payment.rothAmount);
    const verifiedPayment = verifiedStripePaidGbpSession(sessionData, {
      ownerId: businessId,
      expectedAmountGBP: payment.cardAmount,
    });
    const cardAmount = verifiedPayment.amountGBP;
    const requestedMethod = `${payment.requestedPaymentMethod || metadata.requestedPaymentMethod || "card"}`;
    await payBusinessInvoiceAtomically({
      invoiceId,
      businessId,
      cardAmount,
      rothAmount,
      method: rothAmount > 0 ? `roth_${requestedMethod}` : requestedMethod,
      stripeSessionId: sessionData.id,
      stripePaymentIntentId: sessionData.payment_intent || null,
      paymentId,
      metadata: {
        source: "business_invoice_stripe_finalizer",
        stripeEventId: eventId,
        stripeCheckoutSessionId: sessionData.id,
        stripePaymentIntentId: sessionData.payment_intent || null,
      },
    });
  }
};

exports._private = {
  creditBusinessRoth,
  debitBusinessRoth,
  markInvoicePaid,
  payBusinessInvoiceAtomically,
};
