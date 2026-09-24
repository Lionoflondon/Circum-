/* eslint-disable max-len, require-jsdoc */
"use strict";

const {FieldValue} = require("firebase-admin/firestore");
const {createEmailQueueRecord, normalizeEmail} = require("./email-queue");
const templates = require("./transactional-email-templates");

const text = (value) => `${value || ""}`.trim();

function welcomeEmailId(uid) {
  return `sender_welcome_${text(uid).replace(/[^A-Za-z0-9_-]/g, "_")}`.slice(0, 200);
}

async function persistWelcomeStatus(db, uid, patch) {
  if (!db || !uid) return;
  await db.collection("users").doc(uid).set({
    ...patch,
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
}

async function queueSenderWelcomeEmail({
  db,
  uid,
  email,
  displayName = "",
  starterRothTransactionId,
  source = "sender_account",
  recipientSuppressed = false,
  suppressionReason = "",
}) {
  const cleanUid = text(uid);
  const notificationId = welcomeEmailId(cleanUid);
  if (!cleanUid || !text(starterRothTransactionId)) {
    return {status: "blocked", reason: "starter_roth_not_final", notificationId};
  }

  const recipient = normalizeEmail(email);
  const template = templates.welcome({displayName});
  const invalidReason = recipientSuppressed ? text(suppressionReason) || "recipient_suppressed" :
    !recipient ? "invalid_recipient" : "";
  const payload = {
    notificationId,
    ...(recipient ? {to: recipient} : {}),
    subject: template.subject,
    text: template.text,
    html: template.html,
    preheader: template.preheader,
    heading: template.heading,
    ctaLabel: template.ctaLabel,
    ctaUrl: template.ctaUrl,
    templateId: template.templateId,
    providerTags: template.providerTags,
    eventType: "sender_welcome_ready",
    source: "sender_account",
    sourceCollection: "users",
    sourceDocumentId: cleanUid,
    sourceRequiredStatus: "active",
    sourceRecipientField: "email",
    sourceRequiredFields: {
      starterRothGrantStatus: "granted",
      starterRothTransactionId: text(starterRothTransactionId),
    },
    recipientId: cleanUid,
    recipientRole: "sender",
    senderCategory: "info",
    provider: "resend",
    maxAttempts: 5,
    ...(invalidReason ? {
      status: "suppressed",
      recipientSuppressed: true,
      suppressionReason: invalidReason,
      failureReason: invalidReason,
    } : {
      status: "queued",
      attempts: 0,
    }),
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };

  try {
    const result = await createEmailQueueRecord(db, notificationId, payload);
    const queue = await db.collection("emailQueue").doc(notificationId).get();
    const queueData = queue.exists ? queue.data() || {} : {};
    const status = text(queueData.status || (invalidReason ? "suppressed" : result.status)).toLowerCase();
    await persistWelcomeStatus(db, cleanUid, {
      welcomeEmailStatus: status,
      welcomeEmailQueueId: notificationId,
      welcomeEmailTemplateId: template.templateId,
      welcomeEmailSource: source,
      ...(invalidReason ? {welcomeEmailFailureReason: invalidReason} : {welcomeEmailFailureReason: null}),
      ...(status === "sent" ? {welcomeEmailSentAt: FieldValue.serverTimestamp()} : {}),
    });
    return {status, notificationId, result: result.status};
  } catch (error) {
    await persistWelcomeStatus(db, cleanUid, {
      welcomeEmailStatus: "pending",
      welcomeEmailQueueId: notificationId,
      welcomeEmailTemplateId: template.templateId,
      welcomeEmailSource: source,
      welcomeEmailFailureReason: text(error && error.message) || "queue_write_failed",
    });
    return {status: "pending", notificationId, reason: text(error && error.message) || "queue_write_failed"};
  }
}

module.exports = {welcomeEmailId, queueSenderWelcomeEmail};
