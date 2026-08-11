"use strict";

/* eslint-disable max-len, require-jsdoc */
const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue, FieldPath} = require("firebase-admin/firestore");

const ACTIVE_PAYOUTS = new Set(["requested", "processing"]);
const LEDGER_TYPES = new Set(["delivery_earning", "road_reimbursement", "tip", "waiting_fee", "no_show_fee", "adjustment_credit", "adjustment_debit", "payout_reserved", "payout_completed", "payout_failed_release", "refund", "reversal"]);
const RECENT_ACTIVITY_LIMIT = 50;
const callableRuntime = functions.runWith({enforceAppCheck: true});
const number = (value) => Number.isFinite(Number(value)) ? Number(value) : 0;
const text = (value) => `${value || ""}`.trim().toLowerCase();
const money = (value) => Math.round(number(value) * 100) / 100;

function connectReadiness(profile = {}) {
  const raw = text(profile.stripeConnectStatus || profile.stripeStatus);
  if (profile.payoutsEnabled === true && profile.chargesEnabled !== false) return "ready";
  if (["ready", "enabled", "payouts_enabled", "active"].includes(raw)) return "ready";
  if (["pending", "pending_verification", "under_review"].includes(raw)) return "pending_verification";
  if (["restricted", "requirements_due"].includes(raw)) return "restricted";
  if (["disabled", "rejected", "closed"].includes(raw)) return "disabled";
  return "setup_required";
}

function reconcileLedger(rows = [], wallet = {}, payouts = []) {
  const totals = {delivery_earning: 0, road_reimbursement: 0, tip: 0, waiting_fee: 0, no_show_fee: 0, adjustment_credit: 0, adjustment_debit: 0, payout_reserved: 0, payout_completed: 0, payout_failed_release: 0, refund: 0, reversal: 0};
  const seen = new Set();
  const production = [];
  const quarantined = [];
  for (const row of rows) {
    const id = `${row.id || row.transactionId || ""}`;
    const key = `${row.idempotencyKey || row.transactionId || id}`;
    if (seen.has(key)) continue;
    seen.add(key);
    const type = text(row.type || row.category);
    const fixture = row.isTest === true || row.testData === true || text(row.environment) === "test" || text(row.source).includes("fixture");
    if (fixture) {
      quarantined.push({...row, id, classification: "test_fixture"}); continue;
    }
    if (!LEDGER_TYPES.has(type)) {
      quarantined.push({...row, id, classification: "unclassified"}); continue;
    }
    const amount = Math.abs(number(row.amount));
    if (type === "delivery_earning" && number(row.roadReimbursement) > 0) {
      const road = Math.min(amount, Math.abs(number(row.roadReimbursement)));
      totals.delivery_earning = money(totals.delivery_earning + amount - road);
      totals.road_reimbursement = money(totals.road_reimbursement + road);
    } else {
      totals[type] = money(totals[type] + amount);
    }
    production.push({...row, id, type});
  }
  const credits = totals.delivery_earning + totals.road_reimbursement + totals.tip + totals.waiting_fee + totals.no_show_fee + totals.adjustment_credit + totals.payout_failed_release;
  const debits = totals.adjustment_debit + totals.payout_reserved + totals.refund + totals.reversal;
  const calculatedAvailable = money(credits - debits);
  const storedAvailable = money(wallet.availableBalance || wallet.availableEarnings || wallet.accountBalance);
  const unexplained = money(storedAvailable - calculatedAvailable);
  const pending = money(wallet.pendingBalance || wallet.pendingEarnings);
  const normalizedPayouts = payouts.map((p) => ({...p, status: text(p.status || p.payoutStatus)}));
  return {totals, calculatedAvailable, storedAvailable, pending, unexplained, reconciled: Math.abs(unexplained) < 0.01, production, quarantined, activePayout: normalizedPayouts.find((p) => ACTIVE_PAYOUTS.has(p.status)) || null, latestFailed: normalizedPayouts.find((p) => p.status === "failed") || null};
}

function materializedTotals(wallet = {}) {
  const adjustments = money(wallet.adjustmentsTotal || wallet.adjustmentTotal);
  return {
    delivery_earning: money(wallet.deliveryEarningsTotal || wallet.deliveryEarningTotal || wallet.deliveryTotal),
    road_reimbursement: money(wallet.roadChargeReimbursementsTotal || wallet.roadReimbursementsTotal),
    tip: money(wallet.tipsTotal || wallet.tipTotal || wallet.tipsReceived),
    waiting_fee: money(wallet.waitingFeesTotal || wallet.waitingTotal),
    no_show_fee: money(wallet.noShowFeesTotal || wallet.noShowTotal),
    adjustment_credit: adjustments > 0 ? adjustments : 0,
    adjustment_debit: adjustments < 0 ? Math.abs(adjustments) : 0,
    payout_reserved: money(wallet.pendingWithdrawal),
    payout_completed: money(wallet.totalWithdrawn || wallet.withdrawnEarnings),
    payout_failed_release: money(wallet.payoutFailedReleaseTotal),
    refund: money(wallet.refundTotal),
    reversal: money(wallet.reversalTotal),
  };
}

function payoutState(payouts = []) {
  const normalizedPayouts = payouts.map((p) => ({...p, status: text(p.status || p.payoutStatus)}));
  return {
    activePayout: normalizedPayouts.find((p) => ACTIVE_PAYOUTS.has(p.status)) || null,
    latestFailed: normalizedPayouts.find((p) => p.status === "failed") || null,
  };
}

function materializedSummary({wallet = {}, payouts = [], recentRows = [], profile = {}}) {
  const storedAvailable = money(wallet.availableBalance || wallet.availableEarnings || wallet.accountBalance);
  const pending = money(wallet.pendingBalance || wallet.pendingEarnings);
  const reviewRequired = wallet.payoutReviewRequired === true || wallet.reconciliationRequired === true;
  const activityCount = Number.isFinite(Number(wallet.activityCount || wallet.transactionCount)) ?
    Number(wallet.activityCount || wallet.transactionCount) : recentRows.length;
  return {
    totals: materializedTotals(wallet),
    calculatedAvailable: storedAvailable,
    storedAvailable,
    pending,
    unexplained: reviewRequired ? money(wallet.unexplainedBalance || wallet.reconciliationDelta) : 0,
    reconciled: !reviewRequired,
    production: recentRows,
    quarantined: [],
    ...payoutState(payouts),
    connectReadiness: connectReadiness(profile),
    payoutDestination: profile.payoutDestinationSummary || profile.bankAccountSummary || null,
    activityCount,
    summaryMode: "materialized",
  };
}

function orderedRiderQuery(db, collection, uid, fullReconcile) {
  const query = db.collection(collection).where("riderId", "==", uid).orderBy("createdAt", "desc");
  return fullReconcile ? query.get() : query.limit(RECENT_ACTIVITY_LIMIT).get();
}

function isFinanceAdmin(context) {
  const token = context.auth && context.auth.token || {};
  const role = text(token.role || token.adminRole);
  const roles = Array.isArray(token.roles) ? token.roles.map(text) : [];
  return token.admin === true || token.super_admin === true ||
    [role, ...roles].some((value) => ["super_admin", "finance_admin", "operations_admin"].includes(value));
}

async function loadFullReconciliation(db, riderId) {
  const [walletDoc, riderDoc, profileDoc, walletRows, earningRows, payoutRows] = await Promise.all([
    db.collection("riderEarnings").doc(riderId).get(),
    db.collection("riders").doc(riderId).get(),
    db.collection("riderProfiles").doc(riderId).get(),
    orderedRiderQuery(db, "riderWalletTransactions", riderId, true),
    orderedRiderQuery(db, "riderEarningTransactions", riderId, true),
    orderedRiderQuery(db, "payoutRequests", riderId, true),
  ]);
  const wallet = walletDoc.data() || {};
  const profile = {...(riderDoc.data() || {}), ...(profileDoc.data() || {})};
  const rows = [...walletRows.docs, ...earningRows.docs].map((doc) => ({id: doc.id, ...doc.data()}));
  const payouts = payoutRows.docs.map((doc) => ({id: doc.id, ...doc.data()})).sort((a, b) => number(b.createdAt && b.createdAt.toMillis && b.createdAt.toMillis()) - number(a.createdAt && a.createdAt.toMillis && a.createdAt.toMillis()));
  const result = reconcileLedger(rows, wallet, payouts);
  return {wallet, profile, rows, payouts, result};
}

async function reconcileRiderEarnings({db, riderId, actorId = "system", reason = "scheduled_reconciliation", source = "scheduled"}) {
  const {result} = await loadFullReconciliation(db, riderId);
  const recordRef = db.collection("riderEarningsReconciliations").doc();
  const now = FieldValue.serverTimestamp();
  const patch = {
    reconciliationRequired: !result.reconciled,
    lastReconciliationId: recordRef.id,
    lastReconciledAt: now,
    unexplainedBalance: result.unexplained,
    updatedAt: now,
  };
  await Promise.all([
    recordRef.set({
      riderId,
      actorId,
      reason,
      source,
      status: result.reconciled ? "reconciled" : "review_required",
      calculatedAvailable: result.calculatedAvailable,
      storedAvailable: result.storedAvailable,
      unexplained: result.unexplained,
      productionCount: result.production.length,
      quarantinedCount: result.quarantined.length,
      totals: result.totals,
      createdAt: now,
    }),
    db.collection("riderEarnings").doc(riderId).set(patch, {merge: true}),
  ]);
  return {...result, reconciliationId: recordRef.id};
}

function getRiderEarningsSummary() {
  return callableRuntime.https.onCall(async (data, context) => {
    if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Rider must be signed in.");
    const uid = context.auth.uid;
    const db = getFirestore();
    const fullReconcile = data && data.fullReconcile === true;
    const [walletDoc, riderDoc, profileDoc, walletRows, earningRows, payoutRows] = await Promise.all([
      db.collection("riderEarnings").doc(uid).get(), db.collection("riders").doc(uid).get(), db.collection("riderProfiles").doc(uid).get(),
      orderedRiderQuery(db, "riderWalletTransactions", uid, fullReconcile),
      orderedRiderQuery(db, "riderEarningTransactions", uid, fullReconcile),
      orderedRiderQuery(db, "payoutRequests", uid, fullReconcile),
    ]);
    const wallet = walletDoc.data() || {};
    const profile = {...(riderDoc.data() || {}), ...(profileDoc.data() || {})};
    const rows = [...walletRows.docs, ...earningRows.docs].map((doc) => ({id: doc.id, ...doc.data()}));
    const payouts = payoutRows.docs.map((doc) => ({id: doc.id, ...doc.data()})).sort((a, b) => number(b.createdAt && b.createdAt.toMillis && b.createdAt.toMillis()) - number(a.createdAt && a.createdAt.toMillis && a.createdAt.toMillis()));
    if (!fullReconcile) {
      return materializedSummary({wallet, payouts, recentRows: rows, profile});
    }
    const result = reconcileLedger(rows, wallet, payouts);
    return {...result, connectReadiness: connectReadiness(profile), payoutDestination: profile.payoutDestinationSummary || profile.bankAccountSummary || null, activityCount: result.production.length, summaryMode: "full_reconcile"};
  });
}

function adminReconcileRiderEarnings() {
  return callableRuntime.https.onCall(async (data, context) => {
    if (!context.auth || !isFinanceAdmin(context)) {
      throw new functions.https.HttpsError("permission-denied", "Finance administrator access is required.");
    }
    const riderId = `${data && data.riderId || ""}`.trim();
    const reason = `${data && data.reason || ""}`.trim();
    if (!riderId || reason.length < 5) {
      throw new functions.https.HttpsError("invalid-argument", "Rider and reason are required.");
    }
    const result = await reconcileRiderEarnings({
      db: getFirestore(),
      riderId,
      actorId: context.auth.uid,
      reason,
      source: "admin",
    });
    return {
      ok: true,
      riderId,
      reconciliationId: result.reconciliationId,
      reconciled: result.reconciled,
      unexplained: result.unexplained,
    };
  });
}

const scheduledRiderEarningsReconciliation = functions.pubsub.schedule("every 24 hours").onRun(async () => {
  const db = getFirestore();
  const cursorRef = db.collection("systemJobs").doc("riderEarningsReconciliation");
  const cursorDoc = await cursorRef.get();
  const cursor = `${cursorDoc.data() && cursorDoc.data().lastRiderId || ""}`;
  let query = db.collection("riderEarnings").orderBy(FieldPath.documentId()).limit(25);
  if (cursor) query = query.startAfter(cursor);
  let snapshot = await query.get();
  if (snapshot.empty && cursor) {
    snapshot = await db.collection("riderEarnings").orderBy(FieldPath.documentId()).limit(25).get();
  }
  let reconciled = 0;
  let reviewRequired = 0;
  for (const doc of snapshot.docs) {
    const result = await reconcileRiderEarnings({
      db,
      riderId: doc.id,
      actorId: "system",
      reason: "scheduled_reconciliation",
      source: "scheduled",
    });
    if (result.reconciled) reconciled += 1;
    else reviewRequired += 1;
  }
  await cursorRef.set({
    lastRiderId: snapshot.empty ? null : snapshot.docs[snapshot.docs.length - 1].id,
    processed: snapshot.size,
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  return {scanned: snapshot.size, reconciled, reviewRequired};
});

module.exports = {
  getRiderEarningsSummary,
  adminReconcileRiderEarnings,
  scheduledRiderEarningsReconciliation,
  reconcileLedger,
  connectReadiness,
  materializedSummary,
  materializedTotals,
  reconcileRiderEarnings,
};
