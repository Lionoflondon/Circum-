/* eslint-disable max-len, require-jsdoc */
const {getFirestore} = require("firebase-admin/firestore");
const {enqueueEmail, emailQueueId, normalizeEmail: normalizeQueueEmail} = require("./email-queue");

const text = (value) => `${value || ""}`.trim();

function normalizeEmail(value) {
  return normalizeQueueEmail(value);
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
  return emailQueueId(["gift", giftId, eventType]);
}

async function queueGiftDeliveryEmail({giftId, gift = {}, db = getFirestore()}) {
  let email = normalizeEmail(gift.senderEmail || gift.email);
  const senderId = text(gift.senderId || gift.userId);
  if (!email && senderId) {
    for (const collection of ["users", "senders"]) {
      const sender = await db.collection(collection).doc(senderId).get();
      if (!sender.exists) continue;
      email = normalizeEmail(sender.data() && sender.data().email);
      if (email) break;
    }
  }
  if (!email || !giftId) return null;
  const notificationId = emailNotificationId(giftId, "gift_delivered");
  const message = giftDeliveryEmail({giftId, gift});
  await enqueueEmail(db, {
    id: notificationId,
    to: email,
    subject: message.subject,
    textBody: message.text,
    htmlBody: message.html,
    eventType: "gift_delivered",
    sourceCollection: "giftRequests",
    sourceDocumentId: giftId,
    sourceRequiredStatus: "delivered",
    recipientRole: "sender",
    tags: [{name: "product", value: "gifts"}, {name: "event", value: "gift_delivered"}],
    extra: {giftId: text(giftId), recipientId: senderId},
  });
  return notificationId;
}

module.exports.normalizeEmail = normalizeEmail;
module.exports.giftDeliveryEmail = giftDeliveryEmail;
module.exports.emailNotificationId = emailNotificationId;
module.exports.queueGiftDeliveryEmail = queueGiftDeliveryEmail;
