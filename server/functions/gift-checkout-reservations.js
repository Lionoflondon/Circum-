/* eslint-disable max-len, require-jsdoc */
const {createHash} = require("node:crypto");
const {FieldValue} = require("firebase-admin/firestore");
const {blocked, expireLegacySessions} = require("./legacy-payment-artifacts");
const {applyWalletDebit} = require("./roth-ledger");
const {senderWalletProjectionRecord} = require("./roth-ledger-core");
const {normalizeEmail, roundMoney} = require("./wallet-core");
const VERSION = 1;
const refFor = (db, id) => db.collection("giftCheckoutReservations").doc(id);
const idFor = (giftId) => `gift_${createHash("sha256").update(giftId).digest("hex")}_1`;

async function reserve({db, giftRef, uid, split, paymentMethod, nativePayment}) {
  const reservationRef = refFor(db, idFor(giftRef.id));
  return db.runTransaction(async (tx) => {
    const [giftSnap, existing, origin] = await tx.getAll(giftRef, reservationRef, db.doc(`giftCheckoutOrigins/${giftRef.id}`));
    const gift = giftSnap.data() || {};
    if (!giftSnap.exists || gift.senderId !== uid) throw blocked("Gift ownership changed.", "gift_owner");
    if (existing.exists) {
      const r = existing.data();
      if (r.senderId !== uid || r.giftDraftId !== giftRef.id) throw blocked("Gift reservation ownership mismatch.", "gift_owner");
      if (["paid", "cancelled", "expired", "released"].includes(r.status)) throw blocked("This Gift checkout has ended. Start a new Gift request.", "gift_checkout_terminal");
      if (r.nativePayment !== nativePayment) throw blocked("This Gift already has a checkout on another payment surface. Resume or cancel that checkout first.", "gift_checkout_surface");
      return r;
    }
    if (gift.paymentStatus === "paid") throw blocked("Gift has already been paid.", "gift_paid");
    // Legacy drafts can contain provider objects created before their IDs were stored.
    if (gift.giftCheckoutProtocol !== VERSION || !origin.exists || origin.data().senderId !== uid) {
      throw blocked("An earlier Gift checkout requires provider reconciliation.", "gift_legacy_checkout");
    }
    const total = Math.round(Number(gift.grossGiftBudget || gift.grossBudget) * 100);
    const roth = Math.round(split.walletContributionGbp * 100);
    const external = Math.round(split.remainingGbp * 100);
    if (![total, roth, external].every(Number.isSafeInteger) || total < 5000 || roth < 0 || external < 0 || roth + external !== total) throw blocked("Gift amount requires reconciliation.", "gift_amount");
    const r = {reservationVersion: VERSION, checkoutReservationId: reservationRef.id, giftDraftId: giftRef.id, senderId: uid, senderEmail: gift.senderEmail || null, checkoutGeneration: 1, providerIdempotencyKey: reservationRef.id, rothReservationId: `gift_roth_${giftRef.id}`, currency: "gbp", total, rothAmount: roth, externalAmount: external, paymentMethod, nativePayment, status: "reserved", providerId: null, createdAt: Date.now(), expiresAt: Date.now() + 31 * 60000};
    tx.create(reservationRef, r);
    tx.update(giftRef, {giftCheckoutReservationId: r.checkoutReservationId, paymentMethod, walletContributionGbp: roth / 100, remainingStripeAmountGbp: external / 100, rothApplied: roth / 100, cardAmount: external / 100, paymentKey: r.providerIdempotencyKey});
    return r;
  });
}

async function fund({db, reservation}) {
  if (reservation.rothAmount > 0) await applyWalletDebit({db, userId: reservation.senderId, uid: reservation.senderId, userEmail: reservation.senderEmail, amount: reservation.rothAmount / 100, type: "gift_payment_debit", referenceId: reservation.giftDraftId, transactionId: reservation.rothReservationId, notes: "Roth reserved for Gift checkout.", metadata: {checkoutReservationId: reservation.checkoutReservationId}});
}

async function freezeParams({db, reservation, params}) {
  return db.runTransaction(async (tx) => {
    const ref = refFor(db, reservation.checkoutReservationId);
    const snap = await tx.get(ref); const r = snap.data();
    if (["cancelled", "expired", "released"].includes(r.status)) throw blocked("Gift checkout is closed.", "gift_checkout_terminal");
    if (!r.providerId && Date.now() >= r.expiresAt) throw blocked("The provider response needs reconciliation. Do not start another payment.", "gift_provider_unknown");
    if (r.providerParams) return r.providerParams;
    tx.update(ref, {providerParams: params, status: "creating"});
    return params;
  });
}

async function recordProvider({db, reservation, provider, nativePayment}) {
  const ref = refFor(db, reservation.checkoutReservationId);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref); const r = snap.data();
    if (!r || r.nativePayment !== nativePayment || provider.metadata?.checkoutReservationId !== r.checkoutReservationId || provider.metadata?.senderId !== r.senderId || provider.metadata?.giftDraftId !== r.giftDraftId || provider.currency !== r.currency || Number(nativePayment ? provider.amount : provider.amount_total) !== r.externalAmount) throw blocked("Gift provider binding mismatch.", "gift_provider_binding");
    if (r.status === "released" && r.providerId === provider.id) return;
    if (["released", "cancelled", "expired"].includes(r.status)) throw blocked("Gift checkout is closed.", "gift_checkout_terminal");
    if (r.providerId && r.providerId !== provider.id) throw blocked("Gift provider identity changed.", "gift_provider_identity");
    // Finalization deletes the draft; late/replayed provider events must not recreate it.
    if (r.status === "paid") return;
    tx.update(ref, {providerId: provider.id, status: r.status === "paid" ? "paid" : "open", checkoutUrl: provider.url || null});
    tx.update(db.doc(`giftPaymentDrafts/${r.giftDraftId}`), nativePayment ? {stripePaymentIntentId: provider.id} : {stripeCheckoutSessionId: provider.id});
  });
}

async function legacyGate({db, stripe, giftRef, gift}) {
  const origin = await db.doc(`giftCheckoutOrigins/${giftRef.id}`).get();
  if (gift.giftCheckoutProtocol === VERSION && origin.exists && origin.data().senderId === gift.senderId) return;
  await expireLegacySessions({stripe, knownIds: [gift.stripeCheckoutSessionId], matches: (s) => s.metadata && s.metadata.giftDraftId === giftRef.id});
  if (gift.stripePaymentIntentId) {
    let intent = await stripe.paymentIntents.retrieve(gift.stripePaymentIntentId);
    if (["requires_payment_method", "requires_confirmation", "requires_action", "requires_capture"].includes(intent.status)) intent = await stripe.paymentIntents.cancel(intent.id);
    if (intent.status !== "canceled") throw blocked("An earlier Gift payment requires reconciliation.", "gift_legacy_paid");
  }
  // No automatic legacy replacement: a timed-out old client can still be creating an object.
  await db.doc(`paymentArtifactReconciliations/gift_${giftRef.id}`).set({service: "gifts", giftDraftId: giftRef.id, status: "review_required", reason: "legacy_checkout_identity", updatedAt: Date.now()}, {merge: true});
  throw blocked("This earlier Gift checkout needs reconciliation before a replacement. Do not pay again.", "gift_legacy_checkout");
}

async function release({db, stripe, giftId, uid}) {
  const ref = refFor(db, idFor(giftId)); const snap = await ref.get(); const r = snap.data();
  if (!r || r.senderId !== uid) throw blocked("Gift checkout was not found.", "gift_owner");
  if (r.status === "released") return {cancelled: true, idempotent: true};
  if (r.externalAmount === 0 || r.status === "paid") throw blocked("A paid Gift requires the refund process.", "gift_paid");
  // Unknown provider response remains held. Never infer terminal state from local timeout.
  if (r.externalAmount > 0 && !r.providerId) throw blocked("Provider response is unresolved. Resume this checkout before cancelling.", "gift_provider_unknown");
  if (r.externalAmount > 0) {
    let p = r.nativePayment ? await stripe.paymentIntents.retrieve(r.providerId) : await stripe.checkout.sessions.retrieve(r.providerId);
    if (r.nativePayment) {
      if (["requires_payment_method", "requires_confirmation", "requires_action", "requires_capture"].includes(p.status)) p = await stripe.paymentIntents.cancel(p.id);
      if (p.status !== "canceled") throw blocked("Gift payment is not confirmed cancelled.", "gift_provider_nonterminal");
    } else {
      if (p.status === "open" && p.payment_status !== "paid") p = await stripe.checkout.sessions.expire(p.id);
      if (p.status !== "expired" || p.payment_status === "paid") throw blocked("Gift checkout is not confirmed expired.", "gift_provider_nonterminal");
    }
  }
  return db.runTransaction(async (tx) => {
    const walletId = normalizeEmail(r.senderEmail) || uid;
    const walletRef = db.doc(`wallets/${walletId}`); const projectionRef = db.doc(`senderWallets/${uid}`); const debitRef = db.doc(`walletTransactions/${r.rothReservationId}`); const reversalRef = db.doc(`walletTransactions/release_${r.rothReservationId}`); const giftRef = db.doc(`giftPaymentDrafts/${giftId}`);
    const [fresh, wallet, projection, debit, reversal, gift] = await tx.getAll(ref, walletRef, projectionRef, debitRef, reversalRef, giftRef);
    if (fresh.data().status === "paid" || gift.data()?.paymentStatus === "paid") throw blocked("Gift has been paid.", "gift_paid");
    if (r.rothAmount > 0 && debit.exists && !reversal.exists) {
      if (Math.round(Number(debit.data().amount) * 100) !== -r.rothAmount || (debit.data().uid || debit.data().userId) !== uid || !wallet.exists) throw blocked("Gift debit requires reconciliation.", "gift_debit_binding");
      const before = roundMoney(wallet.data().balance ?? wallet.data().rothCredit);
      const after = roundMoney(before + r.rothAmount / 100); const now = FieldValue.serverTimestamp();
      tx.set(walletRef, {balance: after, rothCredit: after, updatedAt: now}, {merge: true});
      tx.set(projectionRef, senderWalletProjectionRecord({userId: uid, balance: after, frozen: wallet.data().isFrozen === true, version: Number(projection.data()?.version || 0) + 1, createdAt: projection.data()?.createdAt || now, updatedAt: now}), {merge: true});
      tx.create(reversalRef, {transactionId: reversalRef.id, uid, walletId, type: "gift_payment_reservation_release", direction: "credit", amount: r.rothAmount / 100, balanceBefore: before, balanceAfter: after, status: "completed", originalTransactionId: r.rothReservationId, checkoutReservationId: r.checkoutReservationId, createdAt: now});
    }
    tx.update(ref, {status: "released", releasedAt: Date.now()}); tx.update(giftRef, {paymentStatus: "checkout_cancelled"});
    return {cancelled: true};
  });
}
module.exports = {VERSION, idFor, reserve, fund, freezeParams, recordProvider, legacyGate, release};
