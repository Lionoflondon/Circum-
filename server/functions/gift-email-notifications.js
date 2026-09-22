/* eslint-disable max-len, require-jsdoc */
const functions = require("firebase-functions/v1");
const {FieldValue, getFirestore} = require("firebase-admin/firestore");

const EMAIL_PROVIDER = "resend";
const EMAIL_API_URL = "https://api.resend.com/emails";
const DEFAULT_FROM = "Circum <gifts@circumuk.com>";

const text = (value) => `${value || ""}`.trim();

function normalizeEmail(value) {
  const email = text(value).toLowerCase();
  return /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email) ? email : "";
}

function configuredEmail() {
  return {
    apiKey: text(process.env.RESEND_API_KEY),
    from: text(process.env.GIFTS_EMAIL_FROM) || DEFAULT_FROM,
  };
}

function deliveredAtValue(gift = {}) {
  return gift.deliveredAt || gift.deliveryCompletedAt || gift.updatedAt || null;
}

function formatDeliveredAt(value) {
  if (!value) return "";
  const date = typeof value.toDate === "function" ? value.toDate() : new Date(value);
  if (Number.isNaN(date.getTime())) return "";
  return new Intl.DateTimeFormat("en-GB", {
    dateStyle: "long",
    timeStyle: "short",
    timeZone: "Europe/London",
  }).format(date);
}

function escapeHtml(value) {
  return text(value).replace(/[&<>"']/g, (character) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    "\"": "&quot;",
    "'": "&#39;",
  }[character]));
}

function giftDeliveryEmail({giftId, gift = {}}) {
  const recipientName = text(gift.recipientName) || "your recipient";
  const deliveredAt = formatDeliveredAt(deliveredAtValue(gift));
  const reference = text(giftId);
  const timing = deliveredAt ? ` on ${deliveredAt}` : "";
  const subject = "Your Circum gift was delivered";
  const textBody = [
    "Your Circum gift was delivered.",
    "",
    `Your gift to ${recipientName} was marked as delivered${timing}.`,
    reference ? `Gift reference: ${reference}` : "",
    "",
    "This is an essential service email for a gift you sent with Circum.",
    "Open Circum to view your Gifts history.",
  ].filter(Boolean).join("\n");
  const htmlBody = `<!doctype html><html><body style="font-family:Arial,sans-serif;color:#17151f;line-height:1.6"><h1>Your Circum gift was delivered</h1><p>Your gift to <strong>${escapeHtml(recipientName)}</strong> was marked as delivered${timing}.</p>${reference ? `<p style="color:#635f70">Gift reference: ${escapeHtml(reference)}</p>` : ""}<p>This is an essential service email for a gift you sent with Circum.</p><p><a href="https://circumuk.com/?app=gifts" style="color:#5b21b6">Open Circum Gifts</a></p></body></html>`;
  return {subject, text: textBody, html: htmlBody};
}

function emailNotificationId(giftId, eventType) {
  return `gift_${text(giftId)}_${text(eventType)}`.replace(/[^A-Za-z0-9_-]/g, "_").slice(0, 200);
}

async function queueGiftDeliveryEmail({giftId, gift = {}}) {
  let email = normalizeEmail(gift.senderEmail || gift.email);
  const senderId = text(gift.senderId || gift.userId);
  if (!email && senderId) {
    for (const collection of ["users", "senders"]) {
      const sender = await getFirestore().collection(collection).doc(senderId).get();
      if (!sender.exists) continue;
      email = normalizeEmail(sender.data() && sender.data().email);
      if (email) break;
    }
  }
  if (!email || !giftId) return null;
  const notificationId = emailNotificationId(giftId, "gift_delivered");
  const ref = getFirestore().collection("giftEmailNotifications").doc(notificationId);
  await ref.create({
    notificationId,
    giftId: text(giftId),
    eventType: "gift_delivered",
    recipientId: senderId,
    recipientEmail: email,
    status: "pending",
    attempts: 0,
    createdAt: FieldValue.serverTimestamp(),
  }).catch((error) => {
    if (error && error.code !== 6 && error.code !== "already-exists") throw error;
  });
  return notificationId;
}

async function sendResendEmail({to, subject, textBody, htmlBody, idempotencyKey, fetchImpl = null}) {
  const {apiKey, from} = configuredEmail();
  if (!apiKey) return {status: "skipped", reason: "email_provider_not_configured"};
  const transport = fetchImpl || (typeof global !== "undefined" ? global.fetch : null);
  if (typeof transport !== "function") throw new Error("email_transport_unavailable");
  const response = await transport(EMAIL_API_URL, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
      "Idempotency-Key": idempotencyKey,
    },
    body: JSON.stringify({
      from,
      to: [to],
      subject,
      text: textBody,
      html: htmlBody,
      tags: [{name: "product", value: "gifts"}, {name: "event", value: "gift_delivered"}],
    }),
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    const error = new Error(text(payload.message) || `email_provider_http_${response.status}`);
    error.providerCode = text(payload.name) || `http_${response.status}`;
    throw error;
  }
  return {status: "sent", providerId: text(payload.id)};
}

async function deliverGiftEmail(snapshot) {
  const data = snapshot.data() || {};
  if (data.status === "sent" || data.status === "skipped") return data;
  const ref = snapshot.ref;
  const attempts = Number(data.attempts || 0) + 1;
  await ref.set({attempts, lastAttemptAt: FieldValue.serverTimestamp()}, {merge: true});
  const gift = await getFirestore().collection("giftRequests").doc(text(data.giftId)).get();
  const email = normalizeEmail(data.recipientEmail);
  if (!email || !gift.exists) {
    await ref.set({status: "skipped", failureReason: !email ? "recipient_email_missing" : "gift_not_found", updatedAt: FieldValue.serverTimestamp()}, {merge: true});
    return {status: "skipped"};
  }
  const message = giftDeliveryEmail({giftId: data.giftId, gift: gift.data() || {}});
  try {
    const result = await sendResendEmail({
      to: email,
      subject: message.subject,
      textBody: message.text,
      htmlBody: message.html,
      idempotencyKey: data.notificationId,
    });
    await ref.set({
      status: result.status,
      provider: EMAIL_PROVIDER,
      providerId: result.providerId || null,
      failureReason: result.reason || null,
      sentAt: result.status === "sent" ? FieldValue.serverTimestamp() : null,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    return result;
  } catch (error) {
    await ref.set({
      status: "failed",
      provider: EMAIL_PROVIDER,
      failureReason: text(error && (error.providerCode || error.message)) || "email_send_failed",
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    throw error;
  }
}

exports.onGiftEmailNotificationCreated = functions.runWith({
  failurePolicy: true,
  timeoutSeconds: 30,
  secrets: ["RESEND_API_KEY", "GIFTS_EMAIL_FROM"],
}).firestore.document("giftEmailNotifications/{notificationId}").onCreate((snapshot) => deliverGiftEmail(snapshot));

module.exports.normalizeEmail = normalizeEmail;
module.exports.giftDeliveryEmail = giftDeliveryEmail;
module.exports.emailNotificationId = emailNotificationId;
module.exports.queueGiftDeliveryEmail = queueGiftDeliveryEmail;
module.exports.sendResendEmail = sendResendEmail;
module.exports.deliverGiftEmail = deliverGiftEmail;
