/* eslint-disable max-len */
"use strict";

const {randomUUID} = require("node:crypto");
const {getFirestore, FieldPath, FieldValue, Timestamp} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");
const deviceTokenAuthority = require("./device-token-authority");
const {pushMessageFor} = require("./communication-engine");

const PAGE_LIMIT = 100;
const MAX_ATTEMPTS = 5;
const LEASE_MS = 5 * 60 * 1000;
const MAX_AGE_MS = 24 * 60 * 60 * 1000;
const RIDER_JOB_MAX_AGE_MS = 5 * 60 * 1000;
const RETRY_DELAYS_MS = [60000, 5 * 60000, 15 * 60000, 60 * 60000, 4 * 60 * 60000];
const PERMANENT_ERRORS = new Set([
  "messaging/invalid-registration-token", "messaging/registration-token-not-registered", "messaging/invalid-argument",
]);
const INVALID_TOKEN_ERRORS = new Set(["messaging/invalid-registration-token", "messaging/registration-token-not-registered"]);
const SAFE_RETRY_ERRORS = new Set(["messaging/quota-exceeded", "messaging/message-rate-exceeded"]);
const OPEN_DELIVERY_STATUSES = new Set(["requested", "pending", "broadcast", "broadcasted", "awaiting_rider", "finding_rider"]);

const clean = (value) => `${value || ""}`.trim();
function millis(value) {
  if (value && typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  return 0;
}
function isStale(row, now) {
  const createdAt = millis(row.createdAt);
  const ttl = clean(row.type) === "new_delivery" ? RIDER_JOB_MAX_AGE_MS : MAX_AGE_MS;
  return !createdAt || now - createdAt > ttl;
}
function due(row, now) {
  return row.retryable === true && clean(row.pushDeliveryStatus) === "failed" &&
    (!row.nextRetryAt || millis(row.nextRetryAt) <= now);
}
function errorCode(error) {
  return clean(error && error.code).slice(0, 120) || "push_outcome_unknown";
}
async function deactivateInvalidToken(db, token, row) {
  const ref = db.collection(deviceTokenAuthority.TOKEN_COLLECTION).doc(deviceTokenAuthority.tokenHash(token));
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return;
    const authority = snap.data() || {};
    if (authority.active !== true || authority.uid !== row.recipientId ||
        authority.role !== row.recipientRole) return;
    tx.set(ref, {active: false, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
  });
}
async function sourceIsStale(db, row) {
  if (clean(row.type) !== "new_delivery") return false;
  const deliveryId = clean(row.data && row.data.deliveryId || row.destination && row.destination.bookingId);
  if (!deliveryId) return true;
  const delivery = await db.collection("deliveryRequests").doc(deliveryId).get();
  if (!delivery.exists) return true;
  const current = delivery.data() || {};
  const status = clean(current.status || current.deliveryStatus || current.deliveryState).toLowerCase();
  return !OPEN_DELIVERY_STATUSES.has(status) || Boolean(current.riderId || current.driverId ||
    current.assignedRiderId || current.assignedDriverId);
}

async function claim(db, ref, now) {
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return null;
    const row = snap.data() || {};
    if (!due(row, now)) return null;
    const claimId = randomUUID();
    tx.set(ref, {
      pushDeliveryStatus: "retrying", retryable: false, retryClaimId: claimId,
      retryLeaseExpiresAt: Timestamp.fromMillis(now + LEASE_MS),
      retrySendState: "not_started", lastRetriedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    return {row, claimId};
  });
}

async function writeClaim(db, ref, claimId, patch) {
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const row = snap.data() || {};
    if (!snap.exists || row.pushDeliveryStatus !== "retrying" || row.retryClaimId !== claimId) {
      throw new Error("notification_retry_claim_lost");
    }
    tx.set(ref, {...patch, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
  });
}

async function recoverExpired(db, now) {
  const snapshot = await db.collection("notifications")
      .where("pushDeliveryStatus", "==", "retrying").limit(PAGE_LIMIT).get();
  let recovered = 0;
  let uncertain = 0;
  for (const doc of snapshot.docs) {
    await db.runTransaction(async (tx) => {
      const fresh = await tx.get(doc.ref);
      if (!fresh.exists) return;
      const row = fresh.data() || {};
      if (row.pushDeliveryStatus !== "retrying" || !row.retryLeaseExpiresAt ||
          millis(row.retryLeaseExpiresAt) > now) return;
      const started = row.retrySendState === "started";
      tx.set(doc.ref, {
        pushDeliveryStatus: started ? "manual_review" : "failed",
        retryable: !started, nextRetryAt: started ? null : Timestamp.fromMillis(now),
        failureReason: started ? "push_outcome_unknown_after_worker_exit" : "retry_worker_exited_before_send",
        retryClaimId: FieldValue.delete(), retryLeaseExpiresAt: FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      if (started) uncertain++;
      else recovered++;
    });
  }
  return {recovered, uncertain};
}

async function processNotificationRetriesCore({
  db = getFirestore(), now = Date.now(), sendPush = (message) => getMessaging().send(message),
  ownedToken = (uid, role) => deviceTokenAuthority.ownedProfileToken(uid, role, {db}),
  dryRun = false,
} = {}) {
  if (dryRun) {
    const preview = await db.collection("notifications")
        .where("retryable", "==", true).orderBy(FieldPath.documentId()).limit(PAGE_LIMIT).get();
    return {scanned: preview.size, due: preview.docs.filter((doc) => due(doc.data() || {}, now)).length,
      wouldSkipStale: preview.docs.filter((doc) => due(doc.data() || {}, now) && isStale(doc.data() || {}, now)).length,
      dryRun: true};
  }
  const recovery = await recoverExpired(db, now);
  const cursorRef = db.collection("operationsState").doc("notification_retry_cursor_v2");
  const cursorSnap = await cursorRef.get();
  const cursor = clean((cursorSnap.data() || {}).lastNotificationId);
  const firstPage = () => db.collection("notifications")
      .where("retryable", "==", true).orderBy(FieldPath.documentId()).limit(PAGE_LIMIT).get();
  let query = db.collection("notifications")
      .where("retryable", "==", true).orderBy(FieldPath.documentId()).limit(PAGE_LIMIT);
  if (cursor) query = query.startAfter(cursor);
  let page = await query.get();
  if (page.empty && cursor) page = await firstPage();
  const result = {scanned: page.size, sent: 0, exhausted: 0, retriedLater: 0,
    skipped: 0, uncertain: recovery.uncertain, recovered: recovery.recovered, invalidTokenCleanupFailed: 0};
  for (const doc of page.docs) {
    const claimed = await claim(db, doc.ref, now);
    if (!claimed) continue;
    const {row, claimId} = claimed;
    const stale = isStale(row, now) || await sourceIsStale(db, row);
    if (stale || Number(row.deliveryAttempts || 0) >= MAX_ATTEMPTS) {
      await writeClaim(db, doc.ref, claimId, {
        pushDeliveryStatus: "exhausted", retryable: false, nextRetryAt: null,
        failureReason: stale ? "stale_notification" : "max_attempts",
        retryClaimId: FieldValue.delete(), retryLeaseExpiresAt: FieldValue.delete(),
      });
      result.exhausted++;
      continue;
    }
    const token = await ownedToken(clean(row.recipientId), clean(row.recipientRole));
    if (!token) {
      await writeClaim(db, doc.ref, claimId, {
        pushDeliveryStatus: "skipped", deliveryStatus: "persisted", retryable: false,
        nextRetryAt: null, failureReason: "push_token_missing",
        retryClaimId: FieldValue.delete(), retryLeaseExpiresAt: FieldValue.delete(),
      });
      result.skipped++;
      continue;
    }
    const attempts = Number(row.deliveryAttempts || 0) + 1;
    await writeClaim(db, doc.ref, claimId, {
      retrySendState: "started", deliveryAttempts: attempts, retryCount: attempts,
      lastDeliveryAttemptAt: FieldValue.serverTimestamp(),
    });
    try {
      const messageId = await sendPush(pushMessageFor({
        token,
        payload: {...row, notificationId: doc.id, title: clean(row.title) || "Circum update",
          body: clean(row.body || row.message), type: clean(row.type) || "system"},
        destination: row.destination || {},
      }));
      await writeClaim(db, doc.ref, claimId, {
        pushDeliveryStatus: "sent", deliveryStatus: "sent", deliveryState: "sent",
        messagingId: messageId, sentAt: FieldValue.serverTimestamp(),
        retryable: false, nextRetryAt: null, failureReason: null,
        retryClaimId: FieldValue.delete(), retryLeaseExpiresAt: FieldValue.delete(),
      });
      result.sent++;
    } catch (error) {
      const code = errorCode(error);
      const permanent = PERMANENT_ERRORS.has(code) || attempts >= MAX_ATTEMPTS;
      const safeRetry = !permanent && SAFE_RETRY_ERRORS.has(code);
      await writeClaim(db, doc.ref, claimId, {
        pushDeliveryStatus: permanent ? "exhausted" : safeRetry ? "failed" : "manual_review",
        deliveryStatus: "failed", retryable: safeRetry,
        nextRetryAt: safeRetry ? Timestamp.fromMillis(now + RETRY_DELAYS_MS[Math.min(attempts - 1, RETRY_DELAYS_MS.length - 1)]) : null,
        failureReason: code,
        retryClaimId: FieldValue.delete(), retryLeaseExpiresAt: FieldValue.delete(),
      });
      if (INVALID_TOKEN_ERRORS.has(code)) {
        try {
          await deactivateInvalidToken(db, token, row);
        } catch (_) {
          result.invalidTokenCleanupFailed++;
        }
      }
      if (permanent) result.exhausted++;
      else if (safeRetry) result.retriedLater++;
      else result.uncertain++;
    }
  }
  if (!page.empty) {
    await cursorRef.set({lastNotificationId: page.docs[page.docs.length - 1].id,
      updatedAt: FieldValue.serverTimestamp()}, {merge: true});
  }
  return result;
}

module.exports = {processNotificationRetriesCore, recoverExpired, due, isStale, sourceIsStale};
