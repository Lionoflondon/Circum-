"use strict";

const functions = require("firebase-functions/v1");
const {getFirestore} = require("firebase-admin/firestore");

const ACTIVE_PAYOUTS = new Set(["requested", "processing"]);
const LEDGER_TYPES = new Set(["delivery_earning", "tip", "waiting_fee", "no_show_fee", "adjustment_credit", "adjustment_debit", "payout_reserved", "payout_completed", "payout_failed_release", "refund", "reversal"]);
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
  const totals = {delivery_earning: 0, tip: 0, waiting_fee: 0, no_show_fee: 0, adjustment_credit: 0, adjustment_debit: 0, payout_reserved: 0, payout_completed: 0, payout_failed_release: 0, refund: 0, reversal: 0};
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
    if (fixture) { quarantined.push({...row, id, classification: "test_fixture"}); continue; }
    if (!LEDGER_TYPES.has(type)) { quarantined.push({...row, id, classification: "unclassified"}); continue; }
    totals[type] = money(totals[type] + Math.abs(number(row.amount)));
    production.push({...row, id, type});
  }
  const credits = totals.delivery_earning + totals.tip + totals.waiting_fee + totals.no_show_fee + totals.adjustment_credit + totals.payout_failed_release;
  const debits = totals.adjustment_debit + totals.payout_reserved + totals.refund + totals.reversal;
  const calculatedAvailable = money(credits - debits);
  const storedAvailable = money(wallet.availableBalance || wallet.availableEarnings || wallet.accountBalance);
  const unexplained = money(storedAvailable - calculatedAvailable);
  const pending = money(wallet.pendingBalance || wallet.pendingEarnings);
  const normalizedPayouts = payouts.map((p) => ({...p, status: text(p.status || p.payoutStatus)}));
  return {totals, calculatedAvailable, storedAvailable, pending, unexplained, reconciled: Math.abs(unexplained) < 0.01, production, quarantined, activePayout: normalizedPayouts.find((p) => ACTIVE_PAYOUTS.has(p.status)) || null, latestFailed: normalizedPayouts.find((p) => p.status === "failed") || null};
}

function getRiderEarningsSummary() {
  return functions.https.onCall(async (_data, context) => {
    if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Rider must be signed in.");
    const uid = context.auth.uid;
    const db = getFirestore();
    const [walletDoc, riderDoc, profileDoc, walletRows, earningRows, payoutRows] = await Promise.all([
      db.collection("riderEarnings").doc(uid).get(), db.collection("riders").doc(uid).get(), db.collection("riderProfiles").doc(uid).get(),
      db.collection("riderWalletTransactions").where("riderId", "==", uid).get(),
      db.collection("riderEarningTransactions").where("riderId", "==", uid).get(),
      db.collection("payoutRequests").where("riderId", "==", uid).get(),
    ]);
    const wallet = walletDoc.data() || {};
    const profile = {...(riderDoc.data() || {}), ...(profileDoc.data() || {})};
    const rows = [...walletRows.docs, ...earningRows.docs].map((doc) => ({id: doc.id, ...doc.data()}));
    const payouts = payoutRows.docs.map((doc) => ({id: doc.id, ...doc.data()})).sort((a, b) => number(b.createdAt && b.createdAt.toMillis && b.createdAt.toMillis()) - number(a.createdAt && a.createdAt.toMillis && a.createdAt.toMillis()));
    const result = reconcileLedger(rows, wallet, payouts);
    return {...result, connectReadiness: connectReadiness(profile), payoutDestination: profile.payoutDestinationSummary || profile.bankAccountSummary || null, activityCount: result.production.length};
  });
}

module.exports = {getRiderEarningsSummary, reconcileLedger, connectReadiness};
