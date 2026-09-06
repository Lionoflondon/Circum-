/* eslint-disable max-len, require-jsdoc */
"use strict";
const {FieldValue} = require("firebase-admin/firestore");
const payoutAllocation = require("./rider-payout-allocation");
const rothLedger = require("./roth-ledger");
const {BALANCE_TYPES, TRANSACTION_TYPES} = require("./roth-ledger-core");
const REASONS = new Set(["duplicate_charge", "unauthorised_payment", "fraud", "serious_service_failure", "processor_reversal", "not_completed"]);
const pence = (amount) => payoutAllocation.minor(amount ?? 0);

async function reverseTipEarning({db, tipId, amountPence, providerReference, reason}) {
  if (!REASONS.has(reason) || !Number.isSafeInteger(amountPence) || amountPence <= 0 || !providerReference) throw new Error("Invalid tip reversal");
  const tipRef = db.collection("deliveryTips").doc(tipId);
  return db.runTransaction(async (tx) => {
    const tipSnap = await tx.get(tipRef);
    if (!tipSnap.exists) throw new Error("Tip not found");
    const tip = tipSnap.data();
    if (amountPence > tip.amountPence || tip.currency !== "GBP") throw new Error("Tip reversal amount mismatch");
    const reversedBefore = tip.reversedPence || 0;
    if (amountPence <= reversedBefore) return {reversed: false};
    const delta = amountPence - reversedBefore;
    const earningRef = db.collection("riderEarnings").doc(tip.riderId);
    const originalRef = db.collection("walletTransactions").doc(`delivery_tip_${tip.deliveryId}`);
    const reversalId = `tip_reversal_${tipId}_${amountPence}`;
    const ledgerRef = db.collection("walletTransactions").doc(reversalId);
    const [earningSnap, originalSnap, prior] = await tx.getAll(earningRef, originalRef, ledgerRef);
    if (prior.exists) throw new Error("Tip reversal state mismatch");
    if (originalSnap.exists) {
      const original = originalSnap.data();
      if (original.riderId !== tip.riderId || original.deliveryId !== tip.deliveryId || original.senderId !== tip.senderId ||
          original.currency !== "GBP" || original.amountPence !== tip.amountPence) throw new Error("Original tip earning identity mismatch");
    }
    const allocationQuery = await tx.get(db.collection("riderPayoutAllocations").where("earningId", "==", originalRef.id));
    if (allocationQuery.docs.some((doc) => doc.data().riderId !== tip.riderId)) throw new Error("Tip allocation owner mismatch");
    const allocations = allocationQuery.docs.filter((doc) => doc.data().kind !== "tip_recovery");
    const recoveryAllocations = allocationQuery.docs.filter((doc) => doc.data().kind === "tip_recovery" && doc.data().state === "paid");
    const recoveryReturns = [];
    let recoveryReturnRemaining = delta;
    for (const allocation of recoveryAllocations) {
      const row = allocation.data();
      const amount = Math.min(recoveryReturnRemaining, row.amountPence - (row.refundedPence || 0));
      if (!amount) continue;
      const recoveryId = row.payoutRequestId.replace(/^recovery_/, "");
      const ref = db.collection("tipRecoveries").doc(recoveryId);
      const snapshot = await tx.get(ref);
      if (!snapshot.exists || snapshot.data().riderId !== tip.riderId) throw new Error("Original recovery missing");
      recoveryReturns.push({allocation, ref, amount, row, data: snapshot.data()});
      recoveryReturnRemaining -= amount;
    }
    const paidPence = allocations.filter((doc) => doc.data().state === "paid").reduce((sum, doc) => sum + doc.data().amountPence - (doc.data().providerReturnedPence || 0), 0);
    const unpaidRemaining = Math.max(0, tip.amountPence - paidPence - (tip.unpaidReversedPence || 0));
    const unpaidReversal = Math.min(delta, unpaidRemaining);
    const paidRecovery = delta - unpaidReversal;
    const cancellations = new Map();
    const returnedAllocations = [];
    let releasedPence = 0;
    let pendingReleasedPence = 0;
    let paidReturnedPence = 0;
    for (const allocation of allocations) {
      const row = allocation.data();
      if (row.state !== "reserved" && !(row.state === "paid" && (row.providerReturnedPence || 0) > (row.accountedReturnPence || 0))) continue;
      const requestRef = db.collection("payoutRequests").doc(row.payoutRequestId);
      const request = await tx.get(requestRef);
      if (!request.exists) throw new Error("Payout allocation request missing");
      const payout = request.data();
      if (payout.transferDispatching && !payout.stripeTransferId) throw new Error("Payout transfer reconciliation pending");
      if (payout.stripeTransferId) {
        const returned = (row.providerReturnedPence || 0) - (row.accountedReturnPence || 0);
        if (returned <= 0) continue;
        returnedAllocations.push({allocation, requestRef, returned, row, payout});
        releasedPence += returned;
        if (row.state === "paid") paidReturnedPence += returned;
        else pendingReleasedPence += returned;
      } else if (!cancellations.has(requestRef.path)) {
        const all = await payoutAllocation.readRequestAllocations(tx, db, requestRef.id);
        cancellations.set(requestRef.path, {requestRef, all, amount: pence(payout.amount), reserved: payout.fundsReserved === true, version: payout.reservationVersion || 0});
        if (payout.fundsReserved === true) {
 releasedPence += pence(payout.amount); pendingReleasedPence += pence(payout.amount);
}
      }
    }
    const earning = earningSnap.data() || {};
    const before = pence(earning.availableBalance ?? earning.availableEarnings);
    const credited = originalSnap.exists;
    const after = credited ? before + releasedPence - delta : before;
    const now = FieldValue.serverTimestamp();
    const entry = {transactionId: reversalId, idempotencyKey: reversalId, tipId, deliveryId: tip.deliveryId,
      senderId: tip.senderId, riderId: tip.riderId, userId: tip.riderId, amountPence: delta, amount: delta / 100,
      currency: "GBP", type: "reversal", category: "reversal", direction: "debit", source: "tip_refund",
      originalTransactionId: originalRef.id, providerReference, reason, riderEarningReversed: credited,
      unpaidReversalPence: unpaidReversal, paidRecoveryPence: paidRecovery,
      payoutAllocationIds: allocations.map((doc) => doc.id),
      restoredRecoveryAllocationIds: recoveryReturns.map((item) => item.allocation.id),
      balanceBefore: (before + releasedPence) / 100, balanceAfter: after / 100, status: "completed", createdAt: now};
    let releaseBalance = before;
    for (const item of cancellations.values()) {
      if (item.reserved) {
        payoutAllocation.writePayoutLedger(tx, db, {requestId: item.requestRef.id, version: item.version, riderId: tip.riderId, amountPence: item.amount,
          phase: "released", balanceBeforePence: releaseBalance, balanceAfterPence: releaseBalance + item.amount});
        releaseBalance += item.amount;
      }
      payoutAllocation.setAllocationState(tx, item.all, "released");
      tx.set(item.requestRef, {status: "cancelled", payoutStatus: "cancelled", tipRefundBlocked: true, fundsReserved: false, cancellationReason: "tip_refund", updatedAt: now}, {merge: true});
    }
    for (const item of recoveryReturns) {
      tx.set(item.ref, {unallocatedPence: (item.data.unallocatedPence || 0) + item.amount, updatedAt: now}, {merge: true});
      tx.set(item.allocation.ref, {refundedPence: (item.row.refundedPence || 0) + item.amount, refundReversalId: reversalId, updatedAt: now}, {merge: true});
    }
    for (const item of returnedAllocations) {
      const returnId = `tip_provider_return_${item.allocation.id}_${item.row.providerReturnedPence}`;
      const release = {transactionId: returnId, idempotencyKey: returnId, riderId: tip.riderId, tipId,
        originalTransactionId: originalRef.id, payoutAllocationId: item.allocation.id, payoutRequestId: item.requestRef.id,
        providerReference: item.row.providerReturnId, providerReturnIds: item.row.providerReturnIds || [item.row.providerReturnId], amountPence: item.returned, amount: item.returned / 100,
        currency: "GBP", direction: "credit", type: "tip_provider_return", status: "completed",
        balanceBefore: releaseBalance / 100, balanceAfter: (releaseBalance + item.returned) / 100, createdAt: now};
      tx.create(db.collection("walletTransactions").doc(returnId), release);
      tx.create(db.collection("riderWalletTransactions").doc(returnId), release);
      releaseBalance += item.returned;
      tx.set(item.allocation.ref, {accountedReturnPence: item.row.providerReturnedPence}, {merge: true});
      tx.set(item.requestRef, {amount: (pence(item.payout.amount) - item.returned) / 100,
        riderNetPayout: (pence(item.payout.riderNetPayout) - item.returned) / 100, updatedAt: now}, {merge: true});
    }
    tx.create(ledgerRef, entry);
    if (paidRecovery > 0) {
tx.create(db.collection("tipRecoveries").doc(reversalId), {
      riderId: tip.riderId, tipId, originalTransactionId: originalRef.id, reversalId,
      amountPence: paidRecovery, unallocatedPence: paidRecovery, payoutAllocationIds: allocations.filter((doc) => doc.data().state === "paid").map((doc) => doc.id), createdAt: now,
    });
}
    if (credited) {
      const originalDate = originalSnap.data().createdAt.toDate();
      const originalDay = originalDate.toISOString().slice(0, 10);
      const originalWeek = new Date(Date.UTC(originalDate.getUTCFullYear(), originalDate.getUTCMonth(), originalDate.getUTCDate() - ((originalDate.getUTCDay() + 6) % 7))).toISOString().slice(0, 10);
      const remainingTotal = (pence(earning.tipTotal ?? earning.tipsTotal) - delta) / 100;
      const count = Math.max(0, Number(earning.tipCount || 0) - (amountPence === tip.amountPence ? 1 : 0));
      const stats = {tipTotal: remainingTotal, tipsTotal: remainingTotal, tipCount: count, averageTip: count ? Math.round(pence(remainingTotal) / count) / 100 : 0};
      for (const collection of ["riderProfiles", "riders", "driverPerformanceMetrics"]) tx.set(db.collection(collection).doc(tip.riderId), stats, {merge: true});
      tx.create(db.collection("riderWalletTransactions").doc(reversalId), entry);
      tx.set(earningRef, {...stats, availableBalance: after / 100, availableEarnings: after / 100,
        tipsToday: (pence(earning.tipsToday) - (earning.tipsTodayDate === originalDay ? delta : 0)) / 100,
        tipsThisWeek: (pence(earning.tipsThisWeek) - (earning.tipsWeekKey === originalWeek ? delta : 0)) / 100,
        tipTotal: (pence(earning.tipTotal ?? earning.tipsTotal) - delta) / 100,
        tipsTotal: (pence(earning.tipsTotal ?? earning.tipTotal) - delta) / 100,
        pendingWithdrawal: ((pence(earning.pendingWithdrawal) - pendingReleasedPence) / 100),
        totalWithdrawn: (pence(earning.totalWithdrawn) - paidReturnedPence) / 100,
        withdrawnEarnings: (pence(earning.withdrawnEarnings) - paidReturnedPence) / 100,
        tipRecoveryPence: (earning.tipRecoveryPence || 0) + paidRecovery,
        payoutReviewRequired: after < 0 || Number(earning.pendingWithdrawal || 0) > 0,
        updatedAt: now}, {merge: true});
    }
    tx.set(tipRef, {unpaidReversedPence: (tip.unpaidReversedPence || 0) + unpaidReversal, paidReversedPence: (tip.paidReversedPence || 0) + paidRecovery, reversedPence: amountPence, status: amountPence === tip.amountPence ? "refunded" : "partially_refunded",
      refundProviderReference: providerReference, refundedAt: now, updatedAt: now}, {merge: true});
    return {reversed: true, amountPence: delta, recoveryPence: Math.max(0, -after)};
  });
}

async function returnUnpaidTipAllocations({db, stripe, tipId, amountPence}) {
  const tipRef = db.collection("deliveryTips").doc(tipId);
  const tip = await db.runTransaction(async (tx) => {
    const snapshot = await tx.get(tipRef);
    if (!snapshot.exists) throw new Error("Tip missing");
    const current = snapshot.data();
    if (!Number.isSafeInteger(amountPence) || amountPence <= 0 || amountPence > current.amountPence) throw new Error("Invalid tip refund amount");
    if (amountPence <= (current.reversedPence || 0)) return null;
    tx.set(tipRef, {status: "refund_pending", updatedAt: FieldValue.serverTimestamp()}, {merge: true});
    return current;
  });
  if (!tip) return;
  const snapshots = await db.collection("riderPayoutAllocations").where("earningId", "==", `delivery_tip_${tip.deliveryId}`).get();
  let remaining = amountPence;
  for (const doc of snapshots.docs.sort((a, b) => a.id.localeCompare(b.id))) {
    const row = doc.data();
    if (row.state !== "reserved") continue;
    const target = Math.min(remaining, row.amountPence);
    remaining -= target;
    if (!target) continue;
    const requestRef = db.collection("payoutRequests").doc(row.payoutRequestId);
    for (let attempt = 0; attempt < 2; attempt++) {
      const operation = await db.runTransaction(async (tx) => {
        const [request, allocation] = await tx.getAll(requestRef, doc.ref);
        const payout = request.data();
        const current = allocation.data();
        if (!payout || !current || current.riderId !== tip.riderId) throw new Error("Payout allocation identity missing");
        if ((current.providerReturnedPence || 0) >= target) return null;
        if (current.returnPending) return current.returnPending;
        if (payout.transferDispatching && !payout.stripeTransferId) throw new Error("Payout transfer reconciliation pending");
        if (!payout.stripeTransferId) {
          tx.set(requestRef, {tipRefundBlocked: true}, {merge: true});
          return null;
        }
        if (payout.status === "paid") return null;
        const pending = {targetPence: target, amountPence: target - (current.providerReturnedPence || 0),
          transferId: payout.stripeTransferId, key: `tip_return_${tipId}_${doc.id}_${target}`, startedAtMillis: Date.now()};
        tx.set(doc.ref, {returnPending: pending}, {merge: true});
        return pending;
      });
      if (!operation) break;
      if (Date.now() - operation.startedAtMillis > 23 * 60 * 60 * 1000) throw new Error("Tip transfer return needs provider reconciliation");
      const reversal = await stripe.transfers.createReversal(operation.transferId,
          {amount: operation.amountPence, metadata: {tipId}}, {idempotencyKey: operation.key});
      await db.runTransaction(async (tx) => {
        const allocation = await tx.get(doc.ref);
        const current = allocation.data();
        if (current.returnPending && current.returnPending.key === operation.key) {
          tx.create(db.collection("tipTransferReturns").doc(operation.key), {
            tipId, riderId: tip.riderId, payoutAllocationId: doc.id, payoutRequestId: row.payoutRequestId,
            originalTransactionId: `delivery_tip_${tip.deliveryId}`, transferId: operation.transferId,
            amountPence: operation.amountPence, providerReference: reversal.id, createdAt: FieldValue.serverTimestamp(),
          });
          tx.set(doc.ref, {providerReturnedPence: operation.targetPence, providerReturnId: reversal.id,
            providerReturnIds: FieldValue.arrayUnion(reversal.id), returnPending: FieldValue.delete()}, {merge: true});
        }
      });
      if (operation.targetPence >= target) break;
    }
  }
}

async function refundCapturedTip({db, stripe, tipId, reason, actorId}) {
  if (!REASONS.has(reason) || !actorId) throw new Error("Tip refund authority is required");
  const ref = db.collection("deliveryTips").doc(tipId);
  const tip = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new Error("Tip not found");
    const current = snap.data();
    if (current.status === "refunded") return current;
    const audit = db.collection("tipRefundRequests").doc(tipId);
    const existing = await tx.get(audit);
    const requestedPence = existing.exists ? existing.data().amountPence : current.amountPence - (current.reversedPence || 0);
    if (!Number.isSafeInteger(requestedPence) || requestedPence <= 0) throw new Error("Invalid remaining tip refund");
    if (!existing.exists) tx.create(audit, {tipId, reason, actorId, amountPence: requestedPence, createdAt: FieldValue.serverTimestamp()});
    tx.set(ref, {status: "refund_pending", updatedAt: FieldValue.serverTimestamp()}, {merge: true});
    return {...current, requestedPence};
  });
  if (tip.status === "refunded") return {status: "refunded"};
  await returnUnpaidTipAllocations({db, stripe, tipId, amountPence: tip.amountPence});
  let providerReference;
  if (tip.paymentMethod === "roth") {
    const debit = await db.collection("walletTransactions").doc(`wallet_tip_${tip.deliveryId}`).get();
    if (!debit.exists || debit.data().uid !== tip.senderId || debit.data().type !== "delivery_tip" || debit.data().referenceId !== tip.deliveryId || Math.abs(pence(debit.data().amount)) !== tip.amountPence) throw new Error("Tip capture is not confirmed");
    providerReference = `tip_refund_${tipId}`;
    await rothLedger.recordRothMovement({db, userId: tip.senderId, uid: tip.senderId, amount: tip.requestedPence / 100,
      balanceType: BALANCE_TYPES.rothCredit, type: TRANSACTION_TYPES.refundCredit, reason: "Tip refund",
      transactionId: providerReference, idempotencyKey: providerReference, relatedEntityId: tip.deliveryId,
      metadata: {tipId, originalTransactionId: debit.id}});
  } else {
    const refund = await stripe.refunds.create({payment_intent: tip.stripePaymentIntentId, amount: tip.requestedPence,
      metadata: {tipId, reason}}, {idempotencyKey: `tip_refund_${tipId}`});
    if (refund.status !== "succeeded") return {status: "refund_pending", refundId: refund.id};
    providerReference = refund.id;
  }
  await reverseTipEarning({db, tipId, amountPence: tip.amountPence, providerReference, reason});
  return {status: "refunded", providerReference};
}
module.exports = {REASONS, reverseTipEarning, refundCapturedTip, returnUnpaidTipAllocations};
