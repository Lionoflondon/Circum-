/* eslint-disable max-len, require-jsdoc */
"use strict";

const {FieldValue} = require("firebase-admin/firestore");
const {createEmailQueueRecord, normalizeEmail} = require("./email-queue");
const templates = require("./transactional-email-templates");

const text = (value) => `${value || ""}`.trim();

function riderWelcomeEmailId(uid) {
  return `rider_welcome_${text(uid).replace(/[^A-Za-z0-9_-]/g, "_")}`.slice(0, 200);
}

async function persistWelcomeStatus(db, uid, patch) {
  if (!db || !uid) return;
  const statusPatch = {
    ...patch,
    updatedAt: FieldValue.serverTimestamp(),
  };
  await Promise.all([
    db.collection("riders").doc(uid).set(statusPatch, {merge: true}),
    db.collection("riderProfiles").doc(uid).set(statusPatch, {merge: true}),
  ]);
}

async function queueRiderWelcomeEmail({db, uid, email, displayName = ""}) {
  const cleanUid = text(uid);
  const notificationId = riderWelcomeEmailId(cleanUid);
  const recipient = normalizeEmail(email);
  const template = templates.riderWelcome({displayName});
  const invalidReason = recipient ? "" : "invalid_recipient";
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
    eventType: "rider_welcome_ready",
    source: "rider_account",
    sourceCollection: "riderProfiles",
    sourceDocumentId: cleanUid,
    sourceRequiredStatus: "profile_started",
    sourceRecipientField: "email",
    recipientId: cleanUid,
    recipientRole: "rider",
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
      welcomeEmailSource: "rider_account",
      ...(invalidReason ? {welcomeEmailFailureReason: invalidReason} : {welcomeEmailFailureReason: null}),
      ...(status === "sent" ? {welcomeEmailSentAt: FieldValue.serverTimestamp()} : {}),
    });
    return {status, notificationId, result: result.status};
  } catch (error) {
    await persistWelcomeStatus(db, cleanUid, {
      welcomeEmailStatus: "pending",
      welcomeEmailQueueId: notificationId,
      welcomeEmailTemplateId: template.templateId,
      welcomeEmailSource: "rider_account",
      welcomeEmailFailureReason: text(error && error.message) || "queue_write_failed",
    });
    return {status: "pending", notificationId, reason: text(error && error.message) || "queue_write_failed"};
  }
}

module.exports = {riderWelcomeEmailId, queueRiderWelcomeEmail};
