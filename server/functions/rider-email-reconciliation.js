/* eslint-disable max-len, require-jsdoc */
"use strict";

const {FieldPath, Timestamp} = require("firebase-admin/firestore");
const {emailQueueId, normalizeEmail} = require("./email-queue");
const {publishFromEvent, CREATED, UPDATED} = require("./transactional-email-publishers");
const policy = require("./rider-email-policy");

const STREAMS = Object.freeze([
  {key: "application_decision", collection: "riderProfiles", field: "riderAuthorityUpdatedAt", eventType: UPDATED},
  {key: "document_action", collection: "riderDocuments", field: "riderAuthorityUpdatedAt", eventType: UPDATED},
  {key: "earnings", collection: "riderEarningTransactions", field: "createdAt", eventType: CREATED},
  {key: "withdrawal_requested", collection: "payoutRequests", field: "createdAt", eventType: CREATED},
  {key: "payout_paid", collection: "payoutRequests", field: "paidAt", eventType: UPDATED},
  {key: "payout_failed", collection: "payoutRequests", field: "failedAt", eventType: UPDATED},
]);

const text = (value) => `${value || ""}`.trim();
const lower = (value) => text(value).toLowerCase();

function millis(value) {
  if (!value) return 0;
  if (typeof value === "number") return value;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (value.seconds != null || value._seconds != null) return Number(value.seconds ?? value._seconds) * 1000;
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function timestampKey(value) {
  if (value && typeof value === "object" && (value.seconds != null || value._seconds != null)) {
    return `${value.seconds ?? value._seconds}_${value.nanos ?? value._nanoseconds ?? 0}`;
  }
  if (value instanceof Date) return `${value.getTime()}`;
  return text(value);
}

function sourceName(collection, id) {
  return `projects/circum-2797c/databases/(default)/documents/${collection}/${id}`;
}

function riderIdFor(collection, data = {}, documentId = "") {
  if (collection === "riderProfiles") return text(data.riderId || data.uid || documentId);
  return text(data.riderId || data.driverId || data.uid);
}

function communicationId(stream, snapshot) {
  const data = snapshot.data() || {};
  const id = snapshot.id;
  if (stream.key === "application_decision") {
    return emailQueueId(["rider_application", id, lower(data.approvalStatus), timestampKey(data.riderAuthorityUpdatedAt)]);
  }
  if (stream.key === "document_action") {
    return emailQueueId(["rider_document", id, lower(data.status || data.verificationStatus), timestampKey(data.riderAuthorityUpdatedAt)]);
  }
  if (stream.key === "earnings") return emailQueueId(["rider_earning", lower(data.type), id]);
  if (stream.key === "withdrawal_requested") return emailQueueId(["rider_payout", "requested", id, timestampKey(data.createdAt)]);
  if (stream.key === "payout_paid") return emailQueueId(["rider_payout", "paid", id, timestampKey(data.paidAt)]);
  return emailQueueId(["rider_payout", "failed", id, timestampKey(data.failedAt)]);
}

async function profileFor(db, riderId) {
  if (!riderId) return null;
  const snapshot = await db.collection("riderProfiles").doc(riderId).get();
  return snapshot.exists ? snapshot.data() || {} : null;
}

async function candidatesForSnapshot({db, stream, snapshot}) {
  const data = snapshot.data() || {};
  const riderId = riderIdFor(stream.collection, data, snapshot.id);
  const profile = await profileFor(db, riderId);
  if (!profile) return [];
  const email = normalizeEmail(profile.email);
  const base = {
    stream: stream.key,
    riderId,
    email,
    sourceCollection: stream.collection,
    sourceDocumentId: snapshot.id,
    sourceData: data,
    eventAt: millis(data[stream.field]),
    communicationId: communicationId(stream, snapshot),
  };
  if (stream.key === "application_decision" && ["approved", "rejected", "more_information_requested"].includes(lower(data.approvalStatus))) {
    return [{...base, eventType: policy.REQUIRED_EVENTS.APPLICATION_DECISION, sourceRequiredStatus: lower(data.approvalStatus)}];
  }
  if (stream.key === "document_action" && ["rejected", "replacement_requested"].includes(lower(data.status || data.verificationStatus))) {
    return [{...base, eventType: policy.REQUIRED_EVENTS.DOCUMENT_ACTION, sourceRequiredStatus: lower(data.status || data.verificationStatus)}];
  }
  if (stream.key === "earnings" && lower(data.status) === "completed" &&
      ["delivery_earning", "cancellation_compensation", "no_show_compensation", "adjustment_credit"].includes(lower(data.type))) {
    const type = lower(data.type);
    return [{...base, eventType: type === "delivery_earning" ? policy.REQUIRED_EVENTS.DELIVERY_EARNINGS :
      ["cancellation_compensation", "no_show_compensation"].includes(type) ? policy.REQUIRED_EVENTS.COMPENSATION : policy.REQUIRED_EVENTS.EARNINGS_ADJUSTMENT,
    sourceRequiredStatus: "completed"}];
  }
  if (stream.key === "withdrawal_requested" && lower(data.status || data.payoutStatus) === "requested") {
    return [{...base, eventType: policy.REQUIRED_EVENTS.WITHDRAWAL_REQUESTED, sourceRequiredStatus: "requested"}];
  }
  if (stream.key === "payout_paid" && lower(data.payoutStatus || data.status) === "paid") {
    return [{...base, eventType: policy.REQUIRED_EVENTS.PAYOUT_PAID, sourceRequiredStatus: "paid"}];
  }
  if (stream.key === "payout_failed" && ["failed", "canceled", "cancelled"].includes(lower(data.payoutStatus || data.status))) {
    return [{...base, eventType: policy.REQUIRED_EVENTS.PAYOUT_FAILED, sourceRequiredStatus: lower(data.payoutStatus || data.status)}];
  }
  return [];
}

function decodedForCandidate(candidate) {
  const before = {};
  if (candidate.stream === "application_decision") before.approvalStatus = "pending";
  if (candidate.stream === "document_action") before.status = "pending";
  if (candidate.stream === "payout_paid" || candidate.stream === "payout_failed") before.payoutStatus = "pending";
  return {documentName: sourceName(candidate.sourceCollection, candidate.sourceDocumentId), before, after: candidate.sourceData};
}

async function stateFor(db, id) {
  const [queue, outcome] = await Promise.all([
    db.collection("emailQueue").doc(id).get(),
    db.collection("riderEmailOutcomes").doc(id).get(),
  ]);
  return {queue: queue.exists, outcome: outcome.exists, existing: queue.exists || outcome.exists};
}

async function recordSuppression(db, candidate, reason) {
  const ref = db.collection("riderEmailOutcomes").doc(candidate.communicationId);
  try {
    await ref.create({
      communicationId: candidate.communicationId,
      policyVersion: policy.POLICY_VERSION,
      eventType: candidate.eventType,
      sourceCollection: candidate.sourceCollection,
      sourceDocumentId: candidate.sourceDocumentId,
      riderId: candidate.riderId,
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

async function reconcileCandidate({db, candidate}) {
  const state = await stateFor(db, candidate.communicationId);
  if (state.existing) return {status: "existing"};
  if (!candidate.email) return {status: await recordSuppression(db, candidate, "invalid_recipient")};
  const result = await publishFromEvent({
    db,
    eventType: candidate.stream === "earnings" || candidate.stream === "withdrawal_requested" ? CREATED : UPDATED,
    eventId: `rider-policy-reconcile-${candidate.communicationId}`,
    decoded: decodedForCandidate(candidate),
  });
  const after = await stateFor(db, candidate.communicationId);
  return {status: after.queue ? (result.status === "duplicate" ? "existing" : "published") : "error"};
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
  return {docs, nextCursor: docs.length === limit && last ? {millis: millis(last.data()[stream.field]), id: last.id} : null};
}

async function runForwardReconciliation({db, startAt, endAt, cursor = {}, pageSize = 50, maxWork = 500, policyEffectiveAt} = {}) {
  if (!db) throw new Error("Firestore is required.");
  if (!Number.isInteger(pageSize) || pageSize < 1 || pageSize > 100) throw new Error("Page size must be 1–100.");
  if (!Number.isInteger(maxWork) || maxWork < 1 || maxWork > 2000) throw new Error("Max work must be 1–2000.");
  const config = policy.policyConfig({effectiveAt: policyEffectiveAt});
  const effective = policy.timestampMillis(config.effectiveAt);
  const start = Math.max(millis(startAt), effective);
  const end = millis(endAt);
  if (!start || !end || end < start) throw new Error("A bounded start and end are required.");
  const result = {policyVersion: config.version, policyEffectiveAt: config.effectiveAt,
    startAt: new Date(start).toISOString(), endAt: new Date(end).toISOString(),
    examined: 0, candidates: 0, published: 0, existing: 0, suppressed: 0, errors: 0, nextCursor: {}, complete: true};
  for (const stream of STREAMS) {
    if (result.examined >= maxWork) {
      result.complete = false;
      result.nextCursor[stream.key] = cursor[stream.key] || null;
      continue;
    }
    const remaining = Math.min(pageSize, maxWork - result.examined);
    const page = await queryStreamPage({db, stream, startAt: start, endAt: end, cursor: cursor[stream.key], limit: remaining});
    result.nextCursor[stream.key] = page.nextCursor;
    for (const snapshot of page.docs) {
      result.examined += 1;
      const eventAt = millis((snapshot.data() || {})[stream.field]);
      if (!policy.isForwardEligible(eventAt, effective) || eventAt > end) continue;
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
  return result;
}

module.exports = {STREAMS, communicationId, runForwardReconciliation, candidatesForSnapshot};
