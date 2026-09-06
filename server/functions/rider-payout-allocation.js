/* eslint-disable max-len, require-jsdoc */
"use strict";
const crypto = require("node:crypto");
const {FieldValue} = require("firebase-admin/firestore");
const CREDIT_TYPES = new Set(["delivery_earning", "tip", "waiting_fee", "no_show_fee", "no_show_compensation", "cancellation_compensation", "adjustment_credit"]);
function minor(value) {
  const scaled = Number(value) * 100;
  if (!Number.isFinite(scaled) || !Number.isSafeInteger(Math.round(scaled)) || Math.abs(scaled - Math.round(scaled)) > 0.000001) throw new Error("Invalid earning amount");
  return Math.round(scaled);
}
function fifoAllocations(earnings, previous, amountPence) {
  if (!Number.isSafeInteger(amountPence) || amountPence <= 0) throw new Error("Invalid payout amount");
  const used = new Map();
  for (const row of previous) {
    if (["reserved", "paid"].includes(row.state)) used.set(row.earningId, (used.get(row.earningId) || 0) + row.amountPence - (row.providerReturnedPence || 0) - (row.refundedPence || 0));
  }
  const seen = new Set();
  const credits = earnings.filter((row) => {
    if (!CREDIT_TYPES.has(row.type) || row.isTest || row.testData || row.amountPence <= 0) return false;
    if (seen.has(row.earningId)) return false;
    seen.add(row.earningId); return true;
  }).sort((a, b) => a.createdMillis - b.createdMillis || a.earningId.localeCompare(b.earningId));
  let remaining = amountPence;
  const result = [];
  for (const row of credits) {
    if (!Number.isFinite(row.createdMillis) || row.createdMillis <= 0) throw new Error("Earning timestamp missing");
    if ((used.get(row.earningId) || 0) > row.amountPence) throw new Error("Earning allocation exceeds credit");
    const available = Math.max(0, row.amountPence - (row.reversedPence || 0) - (used.get(row.earningId) || 0));
    const allocated = Math.min(remaining, available);
    if (allocated > 0) {
result.push({earningId: row.earningId, earningPath: row.path, deliveryId: row.deliveryId || null,
      tipId: row.tipId || null, type: row.type, amountPence: allocated});
}
    remaining -= allocated;
    if (remaining === 0) break;
  }
  if (remaining !== 0) throw new Error("Payout requires earning reconciliation");
  return result;
}
async function readAllocationPlan(tx, db, riderId, requestId, amountPence) {
  const rows = [];
  const historicalPayouts = [];
  for (const name of ["riderEarningTransactions", "riderWalletTransactions"]) {
    const snapshot = await tx.get(db.collection(name).where("riderId", "==", riderId));
    for (const doc of snapshot.docs) {
      const row = doc.data();
      if (["withdrawal", "payout", "payout_completed"].includes(row.type)) historicalPayouts.push(row);
      if (!CREDIT_TYPES.has(row.type)) continue;
      rows.push({...row, earningId: row.idempotencyKey || row.transactionId || doc.id, path: doc.ref.path,
        amountPence: row.amountPence ?? minor(row.amount), createdMillis: row.createdAt && row.createdAt.toMillis ? row.createdAt.toMillis() : 0});
    }
  }
  const allocations = await tx.get(db.collection("riderPayoutAllocations").where("riderId", "==", riderId));
  const previous = allocations.docs.map((d) => d.data());
  const requests = await tx.get(db.collection("payoutRequests").where("riderId", "==", riderId));
  if (requests.docs.some((doc) => doc.id !== requestId && (["reserved", "processing", "scheduled", "paid"].includes(doc.data().status || doc.data().payoutStatus) || doc.data().stripeTransferId) && doc.data().allocationVersion !== 1)) {
    throw new Error("Historical payout lineage requires reconciliation");
  }
  if (historicalPayouts.some((row) => !requests.docs.some((doc) =>
    doc.id === (row.payoutRequestId || row.withdrawalRequestId) && doc.data().allocationVersion === 1))) {
    throw new Error("Historical payout ledger requires reconciliation");
  }
  const own = previous.filter((row) => row.payoutRequestId === requestId && row.state === "reserved");
  if (own.length) {
    if (own.reduce((sum, row) => sum + row.amountPence, 0) !== amountPence) throw new Error("Payout allocation amount changed");
    return {allocations: own, recoveries: []};
  }
  const tips = rows.filter((row) => row.type === "tip");
  if (tips.length) {
    const snapshots = await tx.getAll(...tips.map((row) => db.collection("deliveryTips").doc(row.tipId || row.deliveryId)));
    snapshots.forEach((snapshot, i) => {
      if (!snapshot.exists) throw new Error("Tip authority missing");
      const tip = snapshot.data();
      tips[i].reversedPence = tip.reversedPence || 0;
      if (["refund_pending", "refunded"].includes(tip.status)) tips[i].reversedPence = tips[i].amountPence;
    });
  }
  const recoveryDocs = await tx.get(db.collection("tipRecoveries").where("riderId", "==", riderId));
  const recoveries = [];
  for (const doc of recoveryDocs.docs.sort((a, b) => a.id.localeCompare(b.id))) {
    const recovery = doc.data();
    if (!(recovery.unallocatedPence > 0)) continue;
    const allocated = fifoAllocations(rows, previous, recovery.unallocatedPence);
    previous.push(...allocated.map((row) => ({...row, state: "paid"})));
    recoveries.push({ref: doc.ref, id: doc.id, allocations: allocated});
  }
  return {allocations: fifoAllocations(rows, previous, amountPence), recoveries};
}
function allocationId(requestId, earningId) {
  return crypto.createHash("sha256").update(`${requestId}:${earningId}`).digest("hex");
}
function reserveAllocations(tx, db, riderId, requestId, allocations, state = "reserved", kind = "payout") {
  for (const row of allocations) {
tx.set(db.collection("riderPayoutAllocations").doc(allocationId(requestId, row.earningId)), {
    ...row, riderId, payoutRequestId: requestId, state, kind, updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
}
}
async function readRequestAllocations(tx, db, requestId) {
  return (await tx.get(db.collection("riderPayoutAllocations").where("payoutRequestId", "==", requestId))).docs;
}
function setAllocationState(tx, docs, state, providerReference = null) {
  for (const doc of docs) tx.set(doc.ref, {state, providerReference, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
}
function writePayoutLedger(tx, db, {requestId, version, riderId, amountPence, phase, balanceBeforePence, balanceAfterPence}) {
  const id = `payout_${phase}_${requestId}_${version}`;
  const entry = {transactionId: id, idempotencyKey: id, riderId, userId: riderId, payoutRequestId: requestId,
    type: phase === "reserved" ? "payout_reserved" : "payout_failed_release", amountPence, amount: amountPence / 100,
    direction: phase === "reserved" ? "debit" : "credit", currency: "GBP", status: "completed",
    balanceBefore: balanceBeforePence / 100, balanceAfter: balanceAfterPence / 100, createdAt: FieldValue.serverTimestamp()};
  tx.create(db.collection("riderWalletTransactions").doc(id), entry);
  tx.create(db.collection("walletTransactions").doc(id), entry);
}
module.exports = {writePayoutLedger, minor, fifoAllocations, readAllocationPlan, reserveAllocations, readRequestAllocations, setAllocationState};
