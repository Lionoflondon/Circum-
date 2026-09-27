/* eslint-disable max-len, require-jsdoc */
"use strict";

const {FieldValue} = require("firebase-admin/firestore");
const {calculateWalletCheckout, normalizeEmail} = require("./wallet-core");
const {applyWalletDebit} = require("./roth-ledger");
const reservations = require("./gift-checkout-reservations");
const gifts = require("./gifts-payment");

const INITIAL_ROTH = 57;
const GIFT_BUDGET = 50;
const ACTIONS = new Set(["prepare", "roth_only", "split", "insufficient", "read", "reconcile"]);
const giftId = (fixture, type) => `qa_${type}_${fixture.id}`;

async function seed({qa, fixture, uid, email}) {
  const walletId = normalizeEmail(email);
  if (!walletId || uid !== fixture.senderId) throw new Error("QA Roth Sender identity is unavailable.");
  const walletRef = qa.collection("wallets").doc(walletId);
  const projectionRef = qa.collection("senderWallets").doc(uid);
  return qa.runTransaction(async (tx) => {
    const [wallet, projection] = await tx.getAll(walletRef, projectionRef);
    if (wallet.exists || projection.exists) {
      if (!wallet.exists || !projection.exists || wallet.data().uid !== uid || wallet.data().qaFixtureId !== fixture.id) throw new Error("QA Roth fixture identity changed.");
      return {balance: Number(wallet.data().balance), idempotent: true};
    }
    const now = FieldValue.serverTimestamp();
    tx.create(walletRef, {uid, userId: walletId, userEmail: walletId, normalizedEmail: walletId, balance: INITIAL_ROTH, rothCredit: INITIAL_ROTH, currency: "GBP", isFrozen: false, createdAt: now, updatedAt: now});
    tx.create(projectionRef, {userId: uid, balance: INITIAL_ROTH, rothCredit: INITIAL_ROTH, currency: "ROTH", status: "active", version: 1, createdAt: now, updatedAt: now});
    return {balance: INITIAL_ROTH, idempotent: false};
  });
}

async function prepareDraft({qa, fixture, uid, email, type}) {
  const id = giftId(fixture, type);
  const giftRef = qa.collection("giftRequests").doc(id);
  if ((await giftRef.get()).exists) return {id, paid: true};
  const draftRef = qa.collection("giftPaymentDrafts").doc(id);
  const originRef = qa.collection("giftCheckoutOrigins").doc(id);
  await qa.runTransaction(async (tx) => {
    const [draft, origin] = await tx.getAll(draftRef, originRef);
    if (draft.exists || origin.exists) {
      if (!draft.exists || !origin.exists || draft.data().senderId !== uid || origin.data().senderId !== uid) throw new Error("QA Gift draft identity changed.");
      return;
    }
    const now = FieldValue.serverTimestamp();
    tx.create(draftRef, {giftDraftId: id, senderId: uid, senderEmail: email, recipientName: "Synthetic QA Recipient", recipientEmail: "qa-recipient@example.invalid", deliveryAddress: "Synthetic QA London address", giftMode: "gift_others", grossGiftBudget: GIFT_BUDGET, grossBudget: GIFT_BUDGET, giftCheckoutProtocol: reservations.VERSION, paymentStatus: "payment_pending", giftStatus: "draft", status: "draft", createdAt: now, updatedAt: now});
    tx.create(originRef, {senderId: uid, giftDraftId: id, createdAt: now});
  });
  return {id, paid: false, giftRef: draftRef};
}

async function pay({qa, fixture, uid, email, type, stripe}) {
  const wallet = (await qa.collection("wallets").doc(normalizeEmail(email)).get()).data();
  if (!wallet || wallet.uid !== uid) throw new Error("QA Roth fixture must be prepared first.");
  const draft = await prepareDraft({qa, fixture, uid, email, type});
  if (draft.paid) return {giftId: draft.id, idempotent: true};
  const split = calculateWalletCheckout({orderTotalGbp: GIFT_BUDGET, walletBalanceGbp: wallet.balance, selectedCurrency: "gbp"});
  if (type === "roth_only" && split.remainingGbp !== 0 || type === "split" && split.remainingGbp !== 43) throw new Error("QA Roth balance does not match the fixed payment case.");
  const reservation = await reservations.reserve({db: qa, giftRef: draft.giftRef, uid, split, paymentMethod: type === "roth_only" ? "roth" : "card", nativePayment: type === "split"});
  await reservations.fund({db: qa, reservation});
  let payment;
  if (type === "roth_only") {
    payment = {provider: "roth", providerId: `roth_${draft.id}`, amountPence: 0, currency: "gbp", status: "succeeded", metadata: {giftDraftId: draft.id, senderId: uid}};
  } else {
    const deliveryId = `qa_roth_split_${fixture.id}`;
    await qa.runTransaction(async (tx) => {
      const ref = qa.collection("deliveryRequests").doc(deliveryId);
      const current = await tx.get(ref);
      if (!current.exists) tx.create(ref, {deliveryId, senderId: uid, status: "booked", paymentStatus: "unpaid", isSyntheticQa: true});
    });
    const metadata = {isSyntheticQa: "true", qaFixtureId: fixture.id, deliveryId, checkoutReservationId: reservation.checkoutReservationId, giftDraftId: draft.id, senderId: uid, paymentType: "gift_payment_intent"};
    await reservations.freezeParams({db: qa, reservation, params: {amount: reservation.externalAmount, currency: "gbp", metadata}});
    const intent = await stripe.paymentIntents.create({amount: reservation.externalAmount, currency: "gbp", payment_method: "pm_card_visa", payment_method_types: ["card"], confirm: true, metadata}, {idempotencyKey: reservation.providerIdempotencyKey});
    await reservations.recordProvider({db: qa, reservation, provider: {id: intent.id, amount: intent.amount, currency: intent.currency, metadata: intent.metadata}, nativePayment: true});
    payment = {provider: "payment_intent", providerId: intent.id, paymentIntentId: intent.id, amountPence: intent.amount_received, currency: intent.currency, status: "succeeded", metadata: intent.metadata};
  }
  const finalized = await gifts._private.finalizeGiftPaymentAuthority({db: qa, giftDraftId: draft.id, actorUid: uid, payment, stripe, eventId: `qa_${type}_${fixture.id}`, verifiedVoiceNote: null});
  const gift = (await qa.collection("giftRequests").doc(draft.id).get()).data();
  if (!gift || gift.paymentStatus !== "paid" || gift.walletContributionGbp + gift.remainingStripeAmountGbp !== GIFT_BUDGET) throw new Error("QA Roth payment was not reconciled to one Gift.");
  return {giftId: draft.id, rothApplied: gift.walletContributionGbp, cardAmount: gift.remainingStripeAmountGbp, paymentStatus: gift.paymentStatus, idempotent: finalized.idempotent === true};
}

async function read({qa, fixture, email}) {
  const wallet = (await qa.collection("wallets").doc(normalizeEmail(email)).get()).data();
  const transactions = await qa.collection("walletTransactions").get();
  const gifts = await qa.collection("giftRequests").get();
  return {balance: Number(wallet && wallet.balance || 0), currency: "ROTH", display: "£1 = 1 Roth", completedDebits: transactions.docs.filter((doc) => doc.data().status === "completed" && doc.data().direction === "debit").length, giftCount: gifts.size, fixtureId: fixture.id};
}

async function insufficient({qa, fixture, uid, email}) {
  const before = await read({qa, fixture, email});
  const transactionId = `qa_insufficient_${fixture.id}`;
  try {
    await applyWalletDebit({db: qa, userId: uid, uid, userEmail: email, amount: INITIAL_ROTH + 1, type: "gift_payment_debit", referenceId: transactionId, transactionId});
  } catch (error) {
    if (!/balance is too low/i.test(error.message)) throw error;
    const after = await read({qa, fixture, email});
    if (before.balance !== after.balance || before.completedDebits !== after.completedDebits) throw new Error("Insufficient Roth attempt mutated the ledger.");
    return {rejected: true, balanceUnchanged: true, safeMessage: "Roth balance is too low."};
  }
  throw new Error("Insufficient Roth was unexpectedly accepted.");
}

async function reconcile({qa, fixture, email}) {
  const wallet = (await qa.collection("wallets").doc(normalizeEmail(email)).get()).data();
  const transactions = await qa.collection("walletTransactions").get();
  const debits = transactions.docs.filter((doc) => doc.data().direction === "debit" && doc.data().status === "completed");
  const spent = debits.reduce((sum, doc) => sum - Number(doc.data().amount || 0), 0);
  const mismatch = Math.abs(Number(wallet && wallet.balance || 0) + spent - INITIAL_ROTH) > 0.001;
  const gifts = await qa.collection("giftRequests").get();
  return {fixtureId: fixture.id, examined: debits.length + gifts.size, effective: 0, errors: mismatch ? 1 : 0, balance: Number(wallet && wallet.balance || 0), spent, gifts: gifts.size};
}

module.exports = {ACTIONS, seed, pay, read, insufficient, reconcile};
