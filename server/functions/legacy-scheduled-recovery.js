/* eslint-disable max-len, require-jsdoc */
"use strict";
const {FieldPath, FieldValue, Timestamp} = require("firebase-admin/firestore");
const {reconcileStaleLocks} = require("./stale-lock-recovery");
const {processPendingNoShowSettlements} = require("./legacy-no-show-settlement");
const CONFIG = Object.freeze({
  archiveExpiredDeliveries: {interval: 86400000, collections: ["deliveryRequests", "adminAuditLogs"]},
  processNoShowSettlementRetries: {interval: 300000, collections: ["noShowSettlements", "deliveryRequests", "senderPaymentSessions", "riderEarningTransactions", "platformSettlementTransactions"]},
  reconcileStaleDeliveryLocks: {interval: 900000, collections: ["riderPresence", "staleDeliveryQueue"]},
  migrateBusinessMembershipAuthority: {interval: 600000, collections: ["systemMigrationState", "businessAccounts", "businessMemberships"]},
  cleanupExpiredSenderDrafts: {interval: 86400000, collections: ["senderBookingDrafts"]},
  cleanupExpiredGiftStories: {interval: 3600000, collections: ["giftStoryAccessTokens", "giftRequests"]},
  cleanupExpiredGiftVoiceDrafts: {interval: 86400000, collections: ["giftPaymentDrafts"]},
  scheduledRiderEarningsReconciliation: {interval: 86400000, collections: ["riderEarnings", "riderEarningsReconciliations"]},
  generateHealthPlusRecurringBookings: {interval: 86400000, collections: ["recurringPickupSchedules", "prescriptionPickups"]},
  expireQaLifecycleFixtures: {interval: 900000, collections: ["qaLifecycleFixtures"]},
  expireQaSpecialFlowFixtures: {interval: 600000, collections: ["qaSpecialFlowFixtures"]},
});
async function expiredDrafts({db, now, limit}) {
  const docs = await db.collection("senderBookingDrafts").where("expiresAt", "<=", Timestamp.fromMillis(now)).where("status", "==", "draft").limit(limit).get();
  let deleted = 0;
  for (const doc of docs.docs) {
deleted += await db.runTransaction(async (tx) => {
    const current = await tx.get(doc.ref); const data = current.data() || {};
    if (!current.exists || data.status !== "draft" || !data.expiresAt?.toMillis || data.expiresAt.toMillis() > now) return 0;
    tx.delete(doc.ref); return 1;
  });
}
  return {scanned: docs.size, deleted};
}
async function membershipCompletion({db}) {
  const current = await db.collection("systemMigrationState").doc("business_memberships_v2").get();
  if (!current.exists || current.data().status !== "completed") throw new Error("membership_migration_requires_review");
  return {alreadyCompleted: true, membershipsChanged: 0};
}
async function page({db, collection, worker, limit}) {
  const state = db.collection("operationsState").doc(`legacy_cursor_${worker}`);
  const cursor = (await state.get()).data()?.cursor;
  const query = db.collection(collection).orderBy(FieldPath.documentId()).limit(limit);
  let snapshot = await (cursor ? query.startAfter(cursor) : query).get();
  if (snapshot.empty && cursor) snapshot = await query.get();
  return {snapshot, save: () => state.set({cursor: snapshot.size === limit ? snapshot.docs.at(-1).id : null}, {merge: true})};
}
async function riderReconciliation({db, limit, worker, now: optionsNow = Date.now()}) {
  // Reconciliation observes the ledger and changes only its review metadata.
  // It cannot create charges, payouts, transfers or wallet increments.
  const source = require("./rider-earnings-summary");
  const p = await page({db, collection: "riderEarnings", worker, limit});
  const result = {scanned: p.snapshot.size, reconciled: 0, reviewRequired: 0};
  for (const doc of p.snapshot.docs) {
    const r = await db.runTransaction(async (tx) => {
      const walletRef = db.collection("riderEarnings").doc(doc.id);
      const [wallet, walletRows, earningRows, payouts] = await Promise.all([
        tx.get(walletRef),
        tx.get(db.collection("riderWalletTransactions").where("riderId", "==", doc.id)),
        tx.get(db.collection("riderEarningTransactions").where("riderId", "==", doc.id)),
        tx.get(db.collection("payoutRequests").where("riderId", "==", doc.id)),
      ]);
      const rows = [...walletRows.docs, ...earningRows.docs].map((row) => ({id: row.id, ...row.data()}));
      const value = source.reconcileLedger(rows, wallet.data() || {}, payouts.docs.map((row) => ({id: row.id, ...row.data()})));
      const record = db.collection("riderEarningsReconciliations").doc(`scheduled_${doc.id}_${Math.floor(optionsNow / 86400000)}`);
      tx.set(record, {riderId: doc.id, actorId: "system", source: "scheduled", reason: "scheduled_reconciliation", status: value.reconciled ? "reconciled" : "review_required", calculatedAvailable: value.calculatedAvailable, storedAvailable: value.storedAvailable, unexplained: value.unexplained, productionCount: value.production.length, quarantinedCount: value.quarantined.length, totals: value.totals, createdAt: FieldValue.serverTimestamp()});
      tx.set(walletRef, {reconciliationRequired: !value.reconciled, lastReconciliationId: record.id, lastReconciledAt: FieldValue.serverTimestamp(), unexplainedBalance: value.unexplained, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
      return value;
    });
    if (r.reconciled) result.reconciled++; else result.reviewRequired++;
  }
  await p.save(); return result;
}
async function runLegacyWorker(options) {
  const {worker, db, now = Date.now(), limit = 20, stripe, bucket} = options;
  if (!CONFIG[worker]) throw new Error("unknown_worker");
  if (worker === "archiveExpiredDeliveries") return require("./archive-expired-delivery-recovery").archiveExpired({...options, now, limit});
  if (worker === "processNoShowSettlementRetries") return processPendingNoShowSettlements({db, stripe, limit});
  if (worker === "reconcileStaleDeliveryLocks") return reconcileStaleLocks({db, now, limit});
  if (worker === "migrateBusinessMembershipAuthority") return membershipCompletion({db});
  if (worker === "cleanupExpiredSenderDrafts") return expiredDrafts({db, now, limit});
  if (worker === "scheduledRiderEarningsReconciliation") return riderReconciliation({...options, now, limit});
  if (worker === "cleanupExpiredGiftVoiceDrafts") return require("./gift-voice-cleanup-recovery").cleanupVoice({db, bucket, now, limit});
  if (worker === "cleanupExpiredGiftStories") return require("./gift-story-cleanup-recovery").cleanupGiftStories({db, bucket, now, limit});
  if (worker === "generateHealthPlusRecurringBookings") return require("./health-recurring-recovery").generateRecurring({...options, now, limit});
  if (worker.startsWith("expireQa")) {
    const collection = CONFIG[worker].collections[0];
    const open = await db.collection(collection).where("archived", "==", false).limit(1).get();
    if (!open.empty) throw new Error("qa_cleanup_requires_test_provider_owner");
    return {alreadyArchived: true, openFixtures: 0};
  }
  throw new Error("unknown_worker");
}
module.exports = {CONFIG, runLegacyWorker, expiredDrafts, membershipCompletion, page};
