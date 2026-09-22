/* eslint-disable max-len, require-jsdoc */
"use strict";

const {FieldValue} = require("firebase-admin/firestore");

const EMAIL_QUEUE_COLLECTION = "emailQueue";
const MAX_ID_LENGTH = 200;

const text = (value) => `${value || ""}`.trim();

function normalizeEmail(value) {
  const email = text(value).toLowerCase();
  return /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email) ? email : "";
}

function safeEmailQueueId(value) {
  return text(value).replace(/[^A-Za-z0-9_-]/g, "_").slice(0, MAX_ID_LENGTH);
}

function emailQueueId(parts) {
  return safeEmailQueueId(Array.isArray(parts) ? parts.join("_") : parts);
}

function queueRecord({
  id,
  to,
  subject,
  textBody,
  htmlBody = "",
  eventType,
  sourceCollection = "",
  sourceDocumentId = "",
  sourceRequiredStatus = "",
  recipientRole = "",
  tags = [],
  extra = {},
}) {
  const recipient = normalizeEmail(to);
  if (!recipient || !id || !subject || !textBody) return null;
  return {
    notificationId: id,
    eventType: text(eventType) || "transactional_email",
    to: recipient,
    subject: text(subject),
    text: text(textBody),
    ...(text(htmlBody) ? {html: htmlBody} : {}),
    status: "queued",
    attempts: 0,
    maxAttempts: 5,
    sourceCollection: text(sourceCollection),
    sourceDocumentId: text(sourceDocumentId),
    ...(text(sourceRequiredStatus) ? {sourceRequiredStatus: text(sourceRequiredStatus)} : {}),
    recipientRole: text(recipientRole),
    provider: "resend",
    providerTags: Array.isArray(tags) ? tags : [],
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
    ...extra,
  };
}

async function enqueueEmail(db, record) {
  const payload = queueRecord(record);
  if (!payload) return {status: "skipped", reason: "invalid_email_queue_record"};
  await db.collection(EMAIL_QUEUE_COLLECTION).doc(payload.notificationId).set(payload, {merge: true});
  return {status: "queued", notificationId: payload.notificationId};
}

module.exports = {
  EMAIL_QUEUE_COLLECTION,
  normalizeEmail,
  safeEmailQueueId,
  emailQueueId,
  queueRecord,
  enqueueEmail,
};
