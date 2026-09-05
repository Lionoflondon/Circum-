/* eslint-disable max-len, require-jsdoc */
"use strict";
const functions = require("firebase-functions/v1");
const {FieldValue} = require("firebase-admin/firestore");
const crypto = require("crypto");
const ACTIVE = new Set(["creating", "open", "cancelling"]);
const TERMINAL = new Set(["expired", "cancelled", "failed"]);
const cents = (value) => Math.round(Number(value || 0) * 100);
const pounds = (value) => value / 100;
const fail = (message) =>
  new functions.https.HttpsError("failed-precondition", message);
const reservationRef = (db, id) =>
  db.collection("businessCheckoutReservations").doc(id);
const paymentRef = (db, id) => db.collection("businessInvoicePayments").doc(id);

function remaining(invoice) {
  const amount = cents(
    invoice.balanceDue ??
      Math.max(0, Number(invoice.total || 0) - Number(invoice.amountPaid || 0)),
  );
  if (
    !Number.isSafeInteger(amount) ||
    amount <= 0 ||
    ["paid", "paid_manually", "cancelled", "void"].includes(invoice.status)
  ) {
    throw fail("This invoice cannot accept another payment.");
  }
  return amount;
}
function assertAmount(data, amount) {
  if (data.paymentAmount != null && cents(data.paymentAmount) !== amount) {
    throw fail(
      "The invoice balance changed. Refresh the invoice before paying.",
    );
  }
}
function result(r) {
  return {
    paid: r.status === "paid",
    paymentId: r.checkoutReservationId,
    checkoutReservationId: r.checkoutReservationId,
    sessionId: r.providerSessionId || null,
    checkoutUrl: r.checkoutUrl || null,
    method:
      r.externalAmount === 0 ?
        "roth" :
        r.rothReserved > 0 ?
          "roth_card" :
          "card",
    paymentAmount: pounds(r.amount),
    totalInvoice: pounds(r.amount),
    rothApplied: pounds(r.rothReserved),
    cardAmount: pounds(r.externalAmount),
  };
}

// Legacy provider objects must be terminal before switching an invoice to reservations.
// No timeout or missing Firestore payment record is treated as proof of provider expiry.
async function reconcileLegacy({db, stripe, invoiceId, businessId}) {
  const invoiceRef = db.doc(`businessInvoices/${invoiceId}`);
  const invoice = (await invoiceRef.get()).data() || {};
  if (invoice.checkoutProtocolVersion === 1) return;
  const persisted = await db
    .collection("businessInvoicePayments")
    .where("invoiceId", "==", invoiceId)
    .get();
  const sessions = new Map();
  for (const doc of persisted.docs) {
    const p = doc.data();
    if (
      p.reservationVersion === 1 ||
      ["paid", "expired", "cancelled", "failed"].includes(p.status)
    ) {
      continue;
    }
    const id = p.checkoutSessionId || p.stripeSessionId;
    if (!id) {
      throw fail(
        "A legacy payment requires verification before this invoice can be paid.",
      );
    }
    sessions.set(id, await stripe.checkout.sessions.retrieve(id));
  }
  // The old flow created the Stripe object before writing Firestore. Include orphaned sessions.
  let cursor;
  for (let page = 0; ; page++) {
    if (page >= 100) {
      throw fail(
        "Legacy checkout reconciliation is incomplete. Retry after backend review.",
      );
    }
    const batch = await stripe.checkout.sessions.list({
      limit: 100,
      ...(cursor ? {starting_after: cursor} : {}),
    });
    for (const s of batch.data) {
      if (
        s.metadata &&
        s.metadata.type === "business_invoice_payment" &&
        s.metadata.invoiceId === invoiceId &&
        s.metadata.businessId === businessId
      ) {
        sessions.set(s.id, s);
      }
    }
    if (!batch.has_more) break;
    if (!batch.data.length) {
      throw fail("Legacy provider inventory is incomplete.");
    }
    cursor = batch.data[batch.data.length - 1].id;
  }
  for (let session of sessions.values()) {
    if (session.metadata && session.metadata.checkoutReservationId) continue;
    if (session.payment_status === "paid" || session.status === "complete") {
      const matched = persisted.docs.some((d) => {
        const p = d.data();
        return (
          (p.checkoutSessionId || p.stripeSessionId) === session.id &&
          p.status === "paid"
        );
      });
      if (!matched) {
        throw fail(
          "An earlier payment must finish reconciliation before another checkout.",
        );
      }
      continue;
    }
    if (session.status === "open") {
      session = await stripe.checkout.sessions.expire(session.id);
    }
    if (session.status !== "expired") {
      throw fail("An earlier checkout is still payable or unresolved.");
    }
  }
  await db.runTransaction(async (tx) => {
    const fresh = await tx.get(invoiceRef);
    if (!fresh.exists || fresh.data().businessId !== businessId) {
      throw fail("Invoice ownership changed.");
    }
    tx.update(invoiceRef, {
      checkoutProtocolVersion: 1,
      legacyCheckoutsReconciledAt: FieldValue.serverTimestamp(),
    });
  });
}

async function reserve({
  db,
  invoiceId,
  businessId,
  data,
  uid,
  now = Date.now(),
}) {
  const invoiceRef = db.doc(`businessInvoices/${invoiceId}`);
  const walletRef = db.doc(`business_wallets/${businessId}`);
  return db.runTransaction(async (tx) => {
    const invoiceSnap = await tx.get(invoiceRef);
    if (!invoiceSnap.exists || invoiceSnap.data().businessId !== businessId) {
      throw fail("Invoice Business ownership changed.");
    }
    const invoice = invoiceSnap.data();
    const amount = remaining(invoice);
    assertAmount(data, amount);
    if (invoice.checkoutProtocolVersion !== 1) {
      throw fail("Legacy checkout verification is required.");
    }
    if (invoice.activeCheckoutReservationId) {
      const active = await tx.get(
        reservationRef(db, invoice.activeCheckoutReservationId),
      );
      if (!active.exists) throw fail("Checkout reservation needs recovery.");
      if (ACTIVE.has(active.data().status)) return active.data();
      if (!TERMINAL.has(active.data().status)) {
        throw fail("The previous invoice payment needs reconciliation.");
      }
    }
    const walletSnap = await tx.get(walletRef);
    const wallet = walletSnap.data() || {};
    const balance = cents(wallet.balance ?? wallet.availableBalance ?? 0);
    const reserved = cents(wallet.reservedBalance || 0);
    if (
      !Number.isSafeInteger(balance) ||
      !Number.isSafeInteger(reserved) ||
      reserved < 0 ||
      balance < reserved
    ) {
      throw fail("Business wallet requires reconciliation.");
    }
    const rothReserved =
      data.useRoth === true && (wallet.status || "active") === "active" ?
        Math.min(amount, balance - reserved) :
        0;
    const generation = Number(invoice.checkoutGeneration || 0) + 1;
    const id = `invoice_${crypto.createHash("sha256").update(invoiceId).digest("hex").slice(0, 32)}_${generation}`;
    const r = {
      checkoutReservationId: id,
      reservationVersion: 1,
      businessId,
      invoiceId,
      generation,
      amount,
      currency: "gbp",
      rothReserved,
      externalAmount: amount - rothReserved,
      status: "creating",
      createdAt: now,
      expiresAt: now + 31 * 60 * 1000,
      createdByUserId: uid,
      invoiceNumber: invoice.invoiceNumber || "Circum Business invoice",
      returnUrl: `${data.returnUrl || "https://circumuk.com/?app=business&section=invoicing"}`,
    };
    tx.create(reservationRef(db, id), r);
    tx.create(paymentRef(db, id), {
      ...r,
      amount: pounds(r.externalAmount),
      rothAmount: pounds(rothReserved),
      cardAmount: pounds(r.externalAmount),
      paymentStatus: "pending_verification",
    });
    tx.update(invoiceRef, {
      activeCheckoutReservationId: id,
      checkoutGeneration: generation,
    });
    if (rothReserved > 0) {
      tx.set(
        walletRef,
        {
          reservedBalance: pounds(reserved + rothReserved),
          availableBalance: pounds(balance - reserved - rothReserved),
          updatedAt: FieldValue.serverTimestamp(),
        },
        {merge: true},
      );
      tx.create(walletRef.collection("transactions").doc(`reserve_${id}`), {
        type: "invoice_reservation",
        direction: "reserve",
        amount: pounds(rothReserved),
        invoiceId,
        checkoutReservationId: id,
        createdAt: FieldValue.serverTimestamp(),
      });
    }
    return r;
  });
}
function providerParams(r) {
  const sep = r.returnUrl.includes("?") ? "&" : "?";
  return {
    mode: "payment",
    payment_method_types: ["card"],
    client_reference_id: r.businessId,
    expires_at: Math.floor(r.expiresAt / 1000),
    line_items: [
      {
        quantity: 1,
        price_data: {
          currency: r.currency,
          unit_amount: r.externalAmount,
          product_data: {
            name: r.invoiceNumber,
            description: "Business invoice payment.",
          },
        },
      },
    ],
    success_url: `${r.returnUrl}${sep}paymentStatus=payment-success&invoiceId=${r.invoiceId}&businessId=${r.businessId}&paymentId=${r.checkoutReservationId}&checkoutSessionId={CHECKOUT_SESSION_ID}`,
    cancel_url: `${r.returnUrl}${sep}paymentStatus=payment-cancelled&invoiceId=${r.invoiceId}&businessId=${r.businessId}&paymentId=${r.checkoutReservationId}`,
    metadata: {
      type: "business_invoice_payment",
      businessId: r.businessId,
      invoiceId: r.invoiceId,
      paymentId: r.checkoutReservationId,
      checkoutReservationId: r.checkoutReservationId,
      reservationVersion: "1",
      cardAmountGbp: `${pounds(r.externalAmount)}`,
      rothAmountGbp: `${pounds(r.rothReserved)}`,
      paymentAmountGbp: `${pounds(r.amount)}`,
      createdByUserId: r.createdByUserId,
    },
  };
}
async function provider({db, stripe, reservation}) {
  const r = reservation;
  if (r.providerSessionId) {
    return stripe.checkout.sessions.retrieve(r.providerSessionId);
  }
  // Persisted parameters and key are identical across members/devices and uncertain network retries.
  let session;
  // After a delayed/uncertain creation, recover the provider object even if
  // its idempotency cache has aged out. Never lose an already-paid session.
  if (r.expiresAt <= Date.now()) {
    let cursor;
    for (let page = 0; page < 100; page++) {
      const batch = await stripe.checkout.sessions.list({
        limit: 100,
        ...(cursor ? {starting_after: cursor} : {}),
      });
      for (const candidate of batch.data) {
        if (
          candidate.metadata &&
          candidate.metadata.checkoutReservationId === r.checkoutReservationId
        ) {
          if (session && session.id !== candidate.id) {
            throw fail("Multiple provider objects require reconciliation.");
          }
          session = candidate;
        }
      }
      if (!batch.has_more) break;
      if (page === 99 || !batch.data.length) {
        throw fail("Provider recovery inventory is incomplete.");
      }
      cursor = batch.data[batch.data.length - 1].id;
    }
  }
  if (!session) {
    session = await stripe.checkout.sessions.create(providerParams(r), {
      idempotencyKey: `business_invoice:${r.checkoutReservationId}`,
    });
  }
  await db.runTransaction(async (tx) => {
    const ref = reservationRef(db, r.checkoutReservationId);
    const snap = await tx.get(ref);
    const current = snap.data();
    if (current.providerSessionId && current.providerSessionId !== session.id) {
      throw fail("Provider idempotency conflict.");
    }
    if (!ACTIVE.has(current.status) && current.status !== "paid") {
      throw fail("Checkout is already terminal.");
    }
    const patch = {
      providerSessionId: session.id,
      providerPaymentIntentId: session.payment_intent || null,
      checkoutUrl: session.url || null,
    };
    tx.update(ref, {
      ...patch,
      ...(current.status === "creating" ? {status: "open"} : {}),
    });
    tx.set(
      paymentRef(db, r.checkoutReservationId),
      {...patch, checkoutSessionId: session.id, stripeSessionId: session.id},
      {merge: true},
    );
  });
  return session;
}
async function release({
  db,
  id,
  status,
  providerSession,
  definitiveFailure = false,
}) {
  if (
    !TERMINAL.has(status) ||
    (!definitiveFailure &&
      (!providerSession ||
        providerSession.status !== "expired" ||
        providerSession.payment_status === "paid"))
  ) {
    throw fail("Provider termination has not been confirmed.");
  }
  return db.runTransaction(async (tx) => {
    const ref = reservationRef(db, id);
    const snap = await tx.get(ref);
    const r = snap.data();
    if (TERMINAL.has(r.status)) return r;
    if (!ACTIVE.has(r.status)) {
      throw fail("Payment cannot release reserved Roth.");
    }
    if (
      providerSession &&
      r.providerSessionId &&
      r.providerSessionId !== providerSession.id
    ) {
      throw fail("Wrong checkout session.");
    }
    const walletRef = db.doc(`business_wallets/${r.businessId}`);
    const walletSnap = await tx.get(walletRef);
    const invoiceRef = db.doc(`businessInvoices/${r.invoiceId}`);
    const invoice = await tx.get(invoiceRef);
    const wallet = walletSnap.data() || {};
    const reserved = cents(wallet.reservedBalance || 0);
    if (reserved < r.rothReserved) {
      throw fail("Roth reservation ledger mismatch.");
    }
    tx.update(ref, {status, releasedAt: FieldValue.serverTimestamp()});
    tx.set(paymentRef(db, id), {status, paymentStatus: status}, {merge: true});
    if (invoice.data().activeCheckoutReservationId === id) {
      tx.update(invoiceRef, {activeCheckoutReservationId: FieldValue.delete()});
    }
    if (r.rothReserved > 0) {
      tx.update(walletRef, {
        reservedBalance: pounds(reserved - r.rothReserved),
        availableBalance: pounds(
          cents(wallet.balance ?? wallet.availableBalance) -
            reserved +
            r.rothReserved,
        ),
      });
      tx.create(walletRef.collection("transactions").doc(`release_${id}`), {
        type: "invoice_reservation_release",
        direction: "release",
        amount: pounds(r.rothReserved),
        invoiceId: r.invoiceId,
        checkoutReservationId: id,
        createdAt: FieldValue.serverTimestamp(),
      });
    }
    return {...r, status};
  });
}
async function settle({db, session = null, id}) {
  return db.runTransaction(async (tx) => {
    const ref = reservationRef(db, id);
    const snap = await tx.get(ref);
    if (!snap.exists) throw fail("Checkout reservation not found.");
    const r = snap.data();
    if (r.externalAmount > 0) {
      const m = (session && session.metadata) || {};
      if (
        !session ||
        session.payment_status !== "paid" ||
        session.currency !== r.currency ||
        session.amount_total !== r.externalAmount ||
        m.checkoutReservationId !== id ||
        m.businessId !== r.businessId ||
        m.invoiceId !== r.invoiceId ||
        (r.providerSessionId && session.id !== r.providerSessionId)
      ) {
        throw fail("Provider payment does not match the checkout reservation.");
      }
    } else if (session) {
      throw fail("This reservation does not require a provider payment.");
    }
    if (r.status === "paid") return {paid: true, duplicate: true, ...result(r)};
    if (!ACTIVE.has(r.status)) {
      throw fail("Terminal reservation cannot settle.");
    }
    const invoiceRef = db.doc(`businessInvoices/${r.invoiceId}`);
    const walletRef = db.doc(`business_wallets/${r.businessId}`);
    const [invoiceSnap, walletSnap] = await Promise.all([
      tx.get(invoiceRef),
      tx.get(walletRef),
    ]);
    const invoice = invoiceSnap.data() || {};
    const wallet = walletSnap.data() || {};
    if (
      invoice.businessId !== r.businessId ||
      invoice.activeCheckoutReservationId !== id ||
      remaining(invoice) !== r.amount
    ) {
      throw fail(
        "Invoice changed while payment was pending; reconciliation is required.",
      );
    }
    const balance = cents(wallet.balance ?? wallet.availableBalance ?? 0);
    const reserved = cents(wallet.reservedBalance || 0);
    if (balance < reserved || reserved < r.rothReserved) {
      throw fail("Roth reservation ledger mismatch.");
    }
    const providerPatch = session ?
      {
          providerSessionId: session.id,
          providerPaymentIntentId: session.payment_intent || null,
        } :
      {};
    tx.update(ref, {
      ...providerPatch,
      status: "paid",
      paidAt: FieldValue.serverTimestamp(),
    });
    tx.set(
      paymentRef(db, id),
      {
        ...providerPatch,
        status: "paid",
        paymentStatus: "paid",
        paidAt: FieldValue.serverTimestamp(),
      },
      {merge: true},
    );
    tx.update(invoiceRef, {
      status: "paid",
      amountPaid: pounds(cents(invoice.amountPaid || 0) + r.amount),
      balanceDue: 0,
      activeCheckoutReservationId: FieldValue.delete(),
      paidAt: FieldValue.serverTimestamp(),
      paymentMethod: r.externalAmount ?
        r.rothReserved ?
          "roth_card" :
          "card" :
        "roth",
    });
    if (r.rothReserved > 0) {
      tx.update(walletRef, {
        balance: pounds(balance - r.rothReserved),
        reservedBalance: pounds(reserved - r.rothReserved),
        availableBalance: pounds(balance - reserved),
        lifetimeSpent: FieldValue.increment(pounds(r.rothReserved)),
      });
      tx.create(
        walletRef
          .collection("transactions")
          .doc(`invoice_roth_${r.invoiceId}_${id}`),
        {
          type: "invoice_payment",
          direction: "debit",
          amount: pounds(r.rothReserved),
          invoiceId: r.invoiceId,
          paymentId: id,
          checkoutReservationId: id,
          previousBalance: pounds(balance),
          resultingBalance: pounds(balance - r.rothReserved),
          createdAt: FieldValue.serverTimestamp(),
        },
      );
      tx.set(
        db.doc(`businessAccounts/${r.businessId}`),
        {
          businessRothBalance: pounds(balance - r.rothReserved),
          rothBalance: pounds(balance - r.rothReserved),
        },
        {merge: true},
      );
    }
    tx.create(db.collection("adminAuditLogs").doc(), {
      actionType: "business_invoice_paid",
      businessId: r.businessId,
      invoiceId: r.invoiceId,
      checkoutReservationId: id,
      createdAt: FieldValue.serverTimestamp(),
    });
    return {...result({...r, status: "paid"}), duplicate: false};
  });
}
async function terminate({db, stripe, reservation, status = "cancelled"}) {
  if (reservation.status === "paid") return result(reservation);
  if (reservation.externalAmount === 0) {
    const released = await release({
      db,
      id: reservation.checkoutReservationId,
      status,
      definitiveFailure: true,
    });
    return {cancelled: true, ...result(released)};
  }
  let session = await provider({db, stripe, reservation});
  if (session.payment_status === "paid") {
    return settle({db, session, id: reservation.checkoutReservationId});
  }
  if (session.status === "complete") {
    throw fail("Provider payment is still processing.");
  }
  if (session.status === "open") {
    session = await stripe.checkout.sessions.expire(session.id);
  }
  const released = await release({
    db,
    id: reservation.checkoutReservationId,
    status,
    providerSession: session,
  });
  return {cancelled: true, ...result(released)};
}
async function checkout({
  db,
  stripe,
  invoiceId,
  businessId,
  uid,
  data,
  now = Date.now(),
}) {
  await reconcileLegacy({db, stripe, invoiceId, businessId});
  for (let attempt = 0; attempt < 2; attempt++) {
    const r = await reserve({db, invoiceId, businessId, uid, data, now});
    if (r.externalAmount === 0) {
      return settle({db, id: r.checkoutReservationId});
    }
    let session;
    try {
      session = await provider({db, stripe, reservation: r});
    } catch (error) {
      // A transport timeout is ambiguous: retain the hold and retry the same provider key.
      if (error.type === "StripeInvalidRequestError" && !r.providerSessionId) {
        await release({
          db,
          id: r.checkoutReservationId,
          status: "failed",
          definitiveFailure: true,
        });
      }
      throw error;
    }
    if (session.payment_status === "paid") {
      return settle({db, session, id: r.checkoutReservationId});
    }
    if (session.status === "expired") {
      await release({
        db,
        id: r.checkoutReservationId,
        status: "expired",
        providerSession: session,
      });
      continue;
    }
    if (session.status === "complete") {
      throw fail("Payment is processing. Wait for confirmation.");
    }
    if (r.expiresAt <= now) {
      await terminate({
        db,
        stripe,
        reservation: {...r, providerSessionId: session.id},
        status: "expired",
      });
      continue;
    }
    return result({
      ...r,
      status: "open",
      providerSessionId: session.id,
      checkoutUrl: session.url,
    });
  }
  throw fail("Checkout recovery is in progress. Retry shortly.");
}
async function reconcileExpired({db, stripe, now = Date.now()}) {
  const expired = await db
    .collection("businessCheckoutReservations")
    .where("status", "in", [...ACTIVE])
    .where("expiresAt", "<=", now)
    .limit(100)
    .get();
  const results = [];
  for (const snap of expired.docs) {
    const r = snap.data();
    try {
      results.push(
        await terminate({db, stripe, reservation: r, status: "expired"}),
      );
    } catch (error) {
      if (error.type === "StripeInvalidRequestError" && !r.providerSessionId) {
        await release({
          db,
          id: r.checkoutReservationId,
          status: "failed",
          definitiveFailure: true,
        });
        results.push({
          checkoutReservationId: r.checkoutReservationId,
          status: "failed",
        });
      } else {
        await snap.ref.set(
          {
            recoveryIssue: "provider_state_unconfirmed",
            recoveryAttemptedAt: FieldValue.serverTimestamp(),
          },
          {merge: true},
        );
        results.push({
          checkoutReservationId: r.checkoutReservationId,
          status: "pending_reconciliation",
        });
      }
    }
  }
  return {scanned: expired.size, results};
}
module.exports = {
  reconcileExpired,
  checkout,
  settle,
  terminate,
  reconcileLegacy,
  reserve,
  release,
  providerParams,
  remaining,
};
