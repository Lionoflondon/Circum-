"use strict";

const REFUND_POLICY_VERSION = "2026-08-scheduled-road-charge-refunds-v1";
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {walletIdForEmail} = require("./wallet-core");
const {senderWalletProjectionRecord} = require("./roth-ledger-core");
const STATES = Object.freeze({
  pending: "PENDING_RECONCILIATION",
  eligible: "ELIGIBLE",
  rothSettled: "ROTH_SETTLED",
  cashReserved: "CASH_RESERVED",
  cashSettled: "CASH_SETTLED",
  review: "REVIEW_REQUIRED",
  closed: "CLOSED",
});

function pence(value) {
  const number = Number(value);
  return Number.isFinite(number) ? Math.max(0, Math.round(number)) : 0;
}

function refundableAmountPence(entitlement = {}) {
  return pence(Object.prototype.hasOwnProperty.call(entitlement, "refundablePence") ?
    entitlement.refundablePence : entitlement.entitlementPence);
}

function entitlementId({deliveryId, quoteId, chargeId, lineItemKey} = {}) {
  return [deliveryId, quoteId, chargeId || lineItemKey || "road_charge", REFUND_POLICY_VERSION]
      .map((value) => `${value || ""}`.replace(/[^a-zA-Z0-9:_-]/g, "_"))
      .join(":");
}

function createEntitlement({deliveryId, quoteId, charge, actualEvidence} = {}) {
  const amountPence = pence(charge && (charge.customerContributionPence || charge.amountPence));
  const evidence = actualEvidence && actualEvidence.authoritative === true;
  return {
    entitlementId: entitlementId({
      deliveryId,
      quoteId,
      chargeId: charge && charge.chargeId,
      lineItemKey: charge && charge.key,
    }),
    deliveryId: `${deliveryId || ""}`,
    quoteId: `${quoteId || ""}`,
    chargeId: charge && charge.chargeId || null,
    chargeType: charge && charge.type || null,
    entitlementPence: amountPence,
    refundedPence: 0,
    rothCreditedPence: 0,
    cashRefundedPence: 0,
    state: evidence ? STATES.eligible : STATES.pending,
    actualEvidenceStatus: evidence ? "authoritative" : "unresolved",
    policyVersion: REFUND_POLICY_VERSION,
    refundOwnerType: "sender",
    refundOwnerId: null,
    refundOwnerWalletId: null,
  };
}

async function settleEntitlementToRoth({db = getFirestore(), entitlementId: id, owner = {}} = {}) {
  if (!id) throw new Error("Road-charge refund entitlement is required.");
  const entitlementRef = db.collection("roadChargeRefundEntitlements").doc(id);
  return db.runTransaction(async (transaction) => {
    const entitlementSnapshot = await transaction.get(entitlementRef);
    if (!entitlementSnapshot.exists) return {settled: false, reason: "entitlement_not_found"};
    const entitlement = entitlementSnapshot.data() || {};
    if (entitlement.policyVersion !== REFUND_POLICY_VERSION) {
      return {settled: false, reason: "unsupported_policy_version", entitlementId: id};
    }
    if (!entitlement.deliveryId || !entitlement.quoteId || !entitlement.chargeId) {
      return {settled: false, reason: "malformed_entitlement", entitlementId: id};
    }
    const amountPence = refundableAmountPence(entitlement) -
      pence(entitlement.cashRefundedPence);
    if (entitlement.state === STATES.rothSettled || entitlement.state === STATES.closed) {
      return {settled: false, duplicate: true, entitlementId: id};
    }
    if (entitlement.state !== STATES.eligible || amountPence <= 0) {
      return {settled: false, reason: entitlement.state === STATES.pending ? "evidence_unresolved" : "not_eligible", entitlementId: id};
    }
    const amount = amountPence / 100;
    const ownerType = entitlement.refundOwnerType || owner.type || "sender";
    if (ownerType === "business") {
      const businessId = entitlement.refundOwnerId || owner.id;
      if (!businessId) return {settled: false, reason: "business_owner_missing", entitlementId: id};
      const walletRef = db.collection("business_wallets").doc(businessId);
      const txRef = walletRef.collection("transactions").doc(`road_charge_refund_${id}`);
      const accountRef = db.collection("businessAccounts").doc(businessId);
      const [walletSnapshot, txSnapshot] = await Promise.all([transaction.get(walletRef), transaction.get(txRef)]);
      if (txSnapshot.exists) return {settled: false, duplicate: true, entitlementId: id};
      const previous = Number(walletSnapshot.data() && walletSnapshot.data().balance || 0);
      const resulting = previous + amount;
      transaction.set(walletRef, {businessId, balance: resulting, availableBalance: resulting, lifetimeReceived: FieldValue.increment(amount), updatedAt: FieldValue.serverTimestamp()}, {merge: true});
      transaction.set(accountRef, {businessRothBalance: resulting, rothBalance: resulting, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
      transaction.create(txRef, {transactionId: txRef.id, businessId, direction: "credit", amount, amountGBP: amount, currency: "GBP", type: "scheduled_road_charge_refund", note: "Unused scheduled road charge returned to Business Roth.", relatedEntityId: entitlement.deliveryId, entitlementId: id, createdAt: FieldValue.serverTimestamp(), previousBalance: previous, resultingBalance: resulting, metadata: {policyVersion: REFUND_POLICY_VERSION, quoteId: entitlement.quoteId, chargeId: entitlement.chargeId}});
    } else {
      const uid = entitlement.refundOwnerId || owner.id;
      const email = entitlement.refundOwnerEmail || owner.email || "";
      const walletId = entitlement.refundOwnerWalletId || walletIdForEmail(email) || uid;
      if (!walletId || !uid) return {settled: false, reason: "sender_owner_missing", entitlementId: id};
      const walletRef = db.collection("wallets").doc(walletId);
      const txRef = db.collection("walletTransactions").doc(`road_charge_refund_${id}`);
      const senderRef = db.collection("senderWallets").doc(uid);
      const [walletSnapshot, txSnapshot, senderSnapshot] = await Promise.all([transaction.get(walletRef), transaction.get(txRef), transaction.get(senderRef)]);
      if (txSnapshot.exists) return {settled: false, duplicate: true, entitlementId: id};
      const previous = Number(walletSnapshot.data() && (walletSnapshot.data().balance ?? walletSnapshot.data().rothCredit) || 0);
      const resulting = previous + amount;
      transaction.set(walletRef, {userId: walletId, uid, balance: resulting, rothCredit: resulting, currency: "GBP", updatedAt: FieldValue.serverTimestamp()}, {merge: true});
      transaction.set(senderRef, senderWalletProjectionRecord({userId: uid, balance: resulting, frozen: false, version: Number(senderSnapshot.data() && senderSnapshot.data().version || 0) + 1, createdAt: senderSnapshot.data() && senderSnapshot.data().createdAt || FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()}), {merge: true});
      transaction.create(txRef, {id: txRef.id, transactionId: txRef.id, userId: walletId, uid, walletId, amount, direction: "credit", walletType: "sender", balanceType: "rothCredit", type: "scheduled_road_charge_refund", reason: "Unused scheduled road charge returned to Roth.", relatedEntityId: entitlement.deliveryId, entitlementId: id, status: "completed", createdAt: FieldValue.serverTimestamp(), balanceBefore: previous, balanceAfter: resulting, metadata: {policyVersion: REFUND_POLICY_VERSION, quoteId: entitlement.quoteId, chargeId: entitlement.chargeId}});
    }
    transaction.update(entitlementRef, {state: STATES.rothSettled, refundedPence: amountPence, rothCreditedPence: amountPence, settlementReference: `road_charge_refund_${id}`, settledAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
    return {settled: true, entitlementId: id, amountPence};
  });
}

function eligibleRefund(entitlement, actualEvidence) {
  if (!entitlement || entitlement.policyVersion !== REFUND_POLICY_VERSION) {
    return {eligible: false, reason: "unsupported_policy_version"};
  }
  if (!entitlement || entitlement.state !== STATES.pending && entitlement.state !== STATES.eligible) {
    return {eligible: false, reason: "entitlement_not_open"};
  }
  if (!actualEvidence || actualEvidence.authoritative !== true) {
    return {eligible: false, reason: "actual_incurrence_unresolved"};
  }
  if (actualEvidence.incurred === true) {
    return {eligible: false, reason: "liability_incurred"};
  }
  const amountPence = refundableAmountPence(entitlement) -
    pence(entitlement.rothCreditedPence) - pence(entitlement.cashRefundedPence);
  return amountPence > 0 ? {eligible: true, amountPence} : {eligible: false, reason: "already_settled"};
}

function reserveRoth(entitlement, actualEvidence) {
  const decision = eligibleRefund(entitlement, actualEvidence);
  if (!decision.eligible) return {...entitlement, decision};
  return {...entitlement, state: STATES.rothSettled, rothCreditedPence: decision.amountPence, refundedPence: decision.amountPence, decision};
}

function reserveCash(entitlement, actor = {}) {
  if (!actor.supportAuthorized) return {...entitlement, decision: {eligible: false, reason: "support_authorization_required"}};
  if (!entitlement || entitlement.policyVersion !== REFUND_POLICY_VERSION) {
    return {...entitlement, decision: {eligible: false, reason: "unsupported_policy_version"}};
  }
  if (pence(entitlement.rothCreditedPence) > 0) {
    return {...entitlement, state: STATES.review, decision: {eligible: false, reason: "roth_reversal_required"}};
  }
  if (entitlement.state !== STATES.eligible) return {...entitlement, decision: {eligible: false, reason: "entitlement_not_cash_reservable"}};
  return {...entitlement, state: STATES.cashReserved, decision: {eligible: true, amountPence: pence(entitlement.entitlementPence)}};
}

function settleCash(entitlement) {
  if (!entitlement || entitlement.state !== STATES.cashReserved) return {...entitlement, decision: {eligible: false, reason: "cash_not_reserved"}};
  const amountPence = refundableAmountPence(entitlement);
  return {...entitlement, state: STATES.cashSettled, cashRefundedPence: amountPence, refundedPence: amountPence, decision: {eligible: true, amountPence}};
}

function invariant(entitlement) {
  const total = pence(entitlement && entitlement.rothCreditedPence) + pence(entitlement && entitlement.cashRefundedPence);
  return total <= refundableAmountPence(entitlement);
}

module.exports = {REFUND_POLICY_VERSION, STATES, pence, refundableAmountPence, entitlementId, createEntitlement, eligibleRefund, reserveRoth, reserveCash, settleCash, settleEntitlementToRoth, invariant};
