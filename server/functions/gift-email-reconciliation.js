/* eslint-disable max-len, require-jsdoc */
"use strict";

const {FieldPath, Timestamp} = require("firebase-admin/firestore");
const {getFirestore} = require("firebase-admin/firestore");
const {emailQueueId, normalizeEmail} = require("./email-queue");
const {publishFromEvent, CREATED, UPDATED} = require("./transactional-email-publishers");
const policy = require("./gift-communications-policy");

const STREAMS = Object.freeze([
  {key: "payment_confirmed", collection: "giftRequests", field: "paidAt", eventType: policy.EVENT.PAYMENT_CONFIRMED},
  {key: "payment_problem", collection: "giftPaymentDrafts", field: "paymentProblemAt", eventType: policy.EVENT.PAYMENT_PROBLEM},
  {key: "approved", collection: "giftRequests", field: "approvedAt", eventType: policy.EVENT.APPROVED},
  {key: "rejected", collection: "giftRequests", field: "rejectedAt", eventType: policy.EVENT.REJECTED},
  {key: "ready", collection: "giftRequests", field: "readyForDeliveryAt", eventType: policy.EVENT.READY},
  {key: "delivered", collection: "giftRequests", field: "deliveredAt", eventType: policy.EVENT.DELIVERED},
  {key: "story_ready", collection: "giftRequests", field: "giftStoryAvailableAt", eventType: policy.EVENT.STORY_READY},
]);

const text = (value) => `${value || ""}`.trim();
const lower = (value) => text(value).toLowerCase();

function sourceName(collection, id) {
  return `projects/circum-2797c/databases/(default)/documents/${collection}/${id}`;
}

function timestampKey(value) {
  if (value && typeof value === "object" && (value.seconds != null || value._seconds != null)) {
    return `${value.seconds ?? value._seconds}_${value.nanos ?? value._nanoseconds ?? 0}`;
  }
  if (value instanceof Date) return `${value.getTime()}`;
  return text(value);
}

function paymentAttemptKey(data = {}) {
  return text(data.stripePaymentIntentId || data.stripeCheckoutSessionId) || timestampKey(data.paymentProblemAt);
}

function communicationId(eventType, giftId, role = "", data = {}) {
  if (eventType === policy.EVENT.DELIVERED) return emailQueueId(["gift", giftId, "gift_delivered"]);
  if (eventType === policy.EVENT.STORY_READY) return emailQueueId(["gift_story", giftId, role]);
  if (eventType === policy.EVENT.PAYMENT_PROBLEM) return emailQueueId([eventType, giftId, paymentAttemptKey(data)]);
  return emailQueueId([eventType, giftId]);
}

function communicationOutcomeId(id) {
  return emailQueueId(["gifts_policy", id]);
}

async function readDocument(db, collection, id) {
  const snapshot = await db.collection(collection).doc(id).get();
  return snapshot.exists ? snapshot.data() || {} : null;
}

async function communicationState(db, id) {
  const [queue, outcome] = await Promise.all([
    db.collection("emailQueue").doc(id).get(),
    db.collection("giftCommunicationOutcomes").doc(communicationOutcomeId(id)).get(),
  ]);
  return {queue: queue.exists, outcome: outcome.exists, existing: queue.exists || outcome.exists};
}

async function recordSuppression(db, candidate, reason) {
  const ref = db.collection("giftCommunicationOutcomes").doc(communicationOutcomeId(candidate.communicationId));
  try {
    await ref.create({
      communicationId: candidate.communicationId,
      policyVersion: policy.POLICY_VERSION,
      eventType: candidate.eventType,
      sourceCollection: candidate.sourceCollection,
      sourceDocumentId: candidate.sourceDocumentId,
      recipientRole: candidate.role || "sender",
      status: "suppressed",
      reason,
      authoritativeEventAt: candidate.eventAt ? new Date(candidate.eventAt) : null,
      createdAt: new Date(),
    });
    return "suppressed";
  } catch (error) {
    if (error.code === 6 || error.code === "already-exists" || /already exists/i.test(text(error.message))) return "existing";
    throw error;
  }
}

function eventStatus(eventType) {
  return {
    [policy.EVENT.APPROVED]: "approved",
    [policy.EVENT.REJECTED]: "rejected",
    [policy.EVENT.READY]: "ready_for_gift_delivery",
    [policy.EVENT.DELIVERED]: "delivered",
    [policy.EVENT.STORY_READY]: "unlocked",
  }[eventType] || "";
}

async function giftCandidates({db, giftId, gift, eventType, eventAt, sourceCollection = "giftRequests"}) {
  const candidates = [];
  const sender = normalizeEmail(gift.senderEmail);
  const recipient = normalizeEmail(gift.recipientEmail || gift.recipientContact);
  const base = {giftId, sourceCollection, sourceDocumentId: giftId, eventType, eventAt, sourceData: gift};
  if (eventType === policy.EVENT.PAYMENT_CONFIRMED) {
    const roth = Number(gift.walletContributionGbp || 0);
    const card = Number(gift.remainingStripeAmountGbp || 0);
    if (lower(gift.paymentStatus) !== "paid" || !sender || !Number.isFinite(roth) || roth <= 0 || !Number.isFinite(card) || card < 0) return candidates;
    const ledger = await readDocument(db, "walletTransactions", `gift_roth_${giftId}`);
    if (!ledger || lower(ledger.status) !== "completed" || Number(ledger.amount) !== -roth || text(ledger.referenceId) !== giftId) return candidates;
    candidates.push({...base, role: "sender", email: sender, communicationId: communicationId(eventType, giftId), sourceRequiredStatus: "paid"});
    return candidates;
  }
  if (eventType === policy.EVENT.PAYMENT_PROBLEM) {
    if (!policy.isPaymentProblemState(gift)) return candidates;
    const state = lower(gift.paymentStatus || gift.paymentState || gift.status);
    candidates.push({...base, role: "sender", email: sender, communicationId: communicationId(eventType, giftId, "", gift), sourceRequiredStatus: state, sourcePaymentProblemState: state});
    return candidates;
  }
  if (eventType === policy.EVENT.APPROVED || eventType === policy.EVENT.REJECTED || eventType === policy.EVENT.READY) {
    if (lower(gift.status || gift.giftStatus) !== eventStatus(eventType)) return candidates;
    candidates.push({...base, role: "sender", email: sender, communicationId: communicationId(eventType, giftId), sourceRequiredStatus: eventStatus(eventType)});
    return candidates;
  }
  if (eventType === policy.EVENT.DELIVERED) {
    if (lower(gift.status || gift.giftStatus) !== "delivered") return candidates;
    candidates.push({...base, role: "sender", email: sender, communicationId: communicationId(eventType, giftId), sourceRequiredStatus: "delivered"});
    return candidates;
  }
  if (eventType === policy.EVENT.STORY_READY) {
    if (lower(gift.status || gift.giftStatus) !== "delivered" || gift.giftStoryUnlocked !== true || lower(gift.giftStoryStatus) !== "unlocked") return candidates;
    candidates.push({...base, role: "sender", email: sender, token: text(gift.giftStoryAccessToken), communicationId: communicationId(eventType, giftId, "sender"), sourceRequiredStatus: "unlocked", sourceRecipientField: "senderEmail"});
    candidates.push({...base, role: "recipient", email: recipient, token: text(gift.recipientStoryToken), communicationId: communicationId(eventType, giftId, "recipient"), sourceRequiredStatus: "unlocked", sourceRecipientField: normalizeEmail(gift.recipientEmail) ? "recipientEmail" : "recipientContact"});
  }
  return candidates;
}

async function candidatesForSnapshot({db, stream, snapshot}) {
  const data = snapshot.data() || {};
  const eventAt = policy.authoritativeEventAt(data, stream.eventType).millis;
  if (!eventAt) return [];
  return giftCandidates({db, giftId: snapshot.id, gift: data, eventType: stream.eventType, eventAt, sourceCollection: stream.collection});
}

function decodedForCandidate(candidate) {
  const before = {};
  if (candidate.eventType === policy.EVENT.PAYMENT_CONFIRMED || candidate.eventType === policy.EVENT.PAYMENT_PROBLEM) before.paymentStatus = "payment_pending";
  if (candidate.eventType === policy.EVENT.APPROVED || candidate.eventType === policy.EVENT.REJECTED || candidate.eventType === policy.EVENT.READY) before.status = "submitted_for_review";
  if (candidate.eventType === policy.EVENT.DELIVERED || candidate.eventType === policy.EVENT.STORY_READY) {
    before.status = candidate.eventType === policy.EVENT.DELIVERED ? "approved" : "delivered";
    before.giftStoryStatus = "locked";
  }
  return {documentName: sourceName(candidate.sourceCollection, candidate.sourceDocumentId), before, after: candidate.sourceData};
}

async function publishCandidate({db, candidate}) {
  const result = await publishFromEvent({
    db,
    eventType: candidate.eventType === policy.EVENT.PAYMENT_CONFIRMED ? CREATED : UPDATED,
    eventId: `gift-policy-reconcile-${candidate.communicationId}`,
    decoded: decodedForCandidate(candidate),
  });
  const state = await communicationState(db, candidate.communicationId);
  if (state.queue) return result.status === "duplicate" ? "existing" : "published";
  return "error";
}

async function reconcileCandidate({db, candidate}) {
  const state = await communicationState(db, candidate.communicationId);
  if (state.existing) return {status: "existing"};
  if (!candidate.email) return {status: await recordSuppression(db, candidate, "invalid_recipient")};
  if (candidate.eventType === policy.EVENT.STORY_READY && !/^[A-Za-z0-9_-]{32,}$/.test(candidate.token)) {
    return {status: await recordSuppression(db, candidate, "story_link_missing")};
  }
  return {status: await publishCandidate({db, candidate})};
}

async function queryStreamPage({db, stream, startAt, endAt, cursor, limit}) {
  let query = db.collection(stream.collection)
      .where(stream.field, ">=", Timestamp.fromMillis(startAt))
      .where(stream.field, "<=", Timestamp.fromMillis(endAt))
      .orderBy(stream.field, "asc")
      .orderBy(FieldPath.documentId(), "asc")
      .limit(limit);
  if (cursor && cursor.millis && cursor.id) query = query.startAfter(Timestamp.fromMillis(cursor.millis), cursor.id);
  const page = await query.get();
  const docs = page.docs || [];
  const last = docs.at(-1);
  const nextCursor = docs.length === limit && last ? {millis: policy.timestampMillis(last.data()[stream.field]), id: last.id} : null;
  return {docs, nextCursor};
}

function emptyResult(config, startAt, endAt) {
  return {policyVersion: config.version, policyEffectiveAt: config.effectiveAt,
    startAt: new Date(startAt).toISOString(), endAt: new Date(endAt).toISOString(),
    examined: 0, candidates: 0, published: 0, existing: 0, suppressed: 0, errors: 0,
    nextCursor: {}, complete: true};
}

async function runForwardReconciliation({db, startAt, endAt, cursor = {}, pageSize = 50, maxWork = 500, policyEffectiveAt = null} = {}) {
  if (!db) throw new Error("Firestore is required.");
  if (!Number.isInteger(pageSize) || pageSize < 1 || pageSize > 100) throw new Error("Page size must be 1–100.");
  if (!Number.isInteger(maxWork) || maxWork < 1 || maxWork > 2000) throw new Error("Max work must be 1–2000.");
  const config = policyEffectiveAt ? policy.policyConfig({effectiveAt: policyEffectiveAt}) : await policy.readPolicyConfig({db});
  const effective = policy.timestampMillis(config.effectiveAt);
  const start = Math.max(policy.timestampMillis(startAt), effective);
  const end = policy.timestampMillis(endAt);
  if (!start || !end || end < start) throw new Error("A bounded start and end are required.");
  const result = emptyResult(config, start, end);
  const nextCursor = {};
  for (const stream of STREAMS) {
    if (result.examined >= maxWork) {
      result.complete = false;
      nextCursor[stream.key] = cursor[stream.key] || null;
      continue;
    }
    const remaining = Math.min(pageSize, maxWork - result.examined);
    const page = await queryStreamPage({db, stream, startAt: start, endAt: end, cursor: cursor[stream.key], limit: remaining});
    nextCursor[stream.key] = page.nextCursor;
    for (const snapshot of page.docs) {
      result.examined += 1;
      const data = snapshot.data() || {};
      const eventAt = policy.authoritativeEventAt(data, stream.eventType).millis;
      if (!eventAt || eventAt < effective || eventAt > end) continue;
      const candidates = await candidatesForSnapshot({db, stream, snapshot});
      for (const candidate of candidates) {
        result.candidates += 1;
        const outcome = await reconcileCandidate({db, candidate});
        if (outcome.status === "published") result.published += 1;
        else if (outcome.status === "existing") result.existing += 1;
        else if (outcome.status === "suppressed") result.suppressed += 1;
        else result.errors += 1;
      }
    }
    if (page.docs.length === remaining && page.nextCursor) result.complete = false;
  }
  result.nextCursor = nextCursor;
  return result;
}

async function reconcileGiftById({db, giftId, repair = false, policyEffectiveAt, nowMs = Date.now()} = {}) {
  if (!/^[A-Za-z0-9_-]{1,120}$/.test(text(giftId))) throw new Error("A specific Gift ID is required.");
  const config = policyEffectiveAt ? policy.policyConfig({effectiveAt: policyEffectiveAt}) : await policy.readPolicyConfig({db});
  const gift = await readDocument(db, "giftRequests", giftId);
  if (!gift) return {status: "missing", policyEffectiveAt: config.effectiveAt};
  const candidates = [];
  for (const stream of STREAMS.filter((item) => item.collection === "giftRequests")) {
    const eventAt = policy.authoritativeEventAt(gift, stream.eventType).millis;
    if (eventAt >= policy.timestampMillis(config.effectiveAt) && eventAt <= nowMs) {
      candidates.push(...await giftCandidates({db, giftId, gift, eventType: stream.eventType, eventAt}));
    }
  }
  const counts = {published: 0, existing: 0, suppressed: 0, errors: 0};
  if (repair) {
    for (const candidate of candidates) {
      const outcome = await reconcileCandidate({db, candidate});
      if (Object.prototype.hasOwnProperty.call(counts, outcome.status)) counts[outcome.status] += 1;
      else counts.errors += 1;
    }
  }
  return {status: "inspected", policyVersion: config.version, policyEffectiveAt: config.effectiveAt,
    candidateCount: candidates.length, ...counts};
}

async function scanGiftRecoveryPage({db, kind, afterId = "", limit = 50, policyEffectiveAt, nowMs = Date.now()} = {}) {
  if (!Number.isInteger(limit) || limit < 1 || limit > 100) throw new Error("Scan limit must be 1–100.");
  if (kind !== "paid" && kind !== "deliveries") throw new Error("Choose a bounded forward Gift communications scan.");
  const config = policyEffectiveAt ? policy.policyConfig({effectiveAt: policyEffectiveAt}) : await policy.readPolicyConfig({db});
  const stream = kind === "paid" ? STREAMS[0] : STREAMS[5];
  const page = await queryStreamPage({db, stream, startAt: policy.timestampMillis(config.effectiveAt), endAt: nowMs, cursor: afterId ? {millis: 0, id: afterId} : null, limit});
  const candidates = [];
  for (const snapshot of page.docs) {
    const eventAt = policy.authoritativeEventAt(snapshot.data() || {}, stream.eventType).millis;
    if (eventAt >= policy.timestampMillis(config.effectiveAt)) candidates.push(...await candidatesForSnapshot({db, stream, snapshot}));
  }
  return {kind, policyVersion: config.version, examined: page.docs.length, candidates, nextAfterId: page.nextCursor && page.nextCursor.id || null};
}

if (require.main === module) {
  const {initializeApp} = require("firebase-admin/app");
  const args = new Map(process.argv.slice(2).filter((arg) => arg.startsWith("--")).map((arg) => {
    const index = arg.indexOf("=");
    return index === -1 ? [arg.slice(2), true] : [arg.slice(2, index), arg.slice(index + 1)];
  }));
  initializeApp();
  const db = getFirestore();
  const effectiveAt = text(args.get("effective-at"));
  const operation = args.has("record-policy-cutover") ? policy.recordPolicyConfig({db, effectiveAt, actor: text(args.get("actor")) || "deployment"}) :
    args.has("reconcile-forward") ? runForwardReconciliation({db, startAt: args.get("start"), endAt: args.get("end"),
      cursor: text(args.get("cursor")) ? JSON.parse(Buffer.from(text(args.get("cursor")), "base64url").toString("utf8")) : {},
      pageSize: Number(args.get("page-size") || 50), maxWork: Number(args.get("max-work") || 500)}) :
      args.has("inspect-gift") ? reconcileGiftById({db, giftId: text(args.get("inspect-gift")), repair: args.has("repair"), policyEffectiveAt: effectiveAt || null}) :
        Promise.reject(new Error("Choose --record-policy-cutover, --reconcile-forward, or --inspect-gift."));
  operation.then((result) => process.stdout.write(`${JSON.stringify(result)}\n`)).catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  });
}

module.exports = {STREAMS, communicationId, recordSuppression, reconcileGiftById, runForwardReconciliation, scanGiftRecoveryPage};
