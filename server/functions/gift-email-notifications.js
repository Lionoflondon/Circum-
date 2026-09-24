/* eslint-disable max-len, require-jsdoc */
const {getFirestore} = require("firebase-admin/firestore");
const {enqueueEmail, emailQueueId, normalizeEmail: normalizeQueueEmail} = require("./email-queue");
const templates = require("./transactional-email-templates");

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

function giftDeliveryEmail({giftId, gift = {}}) {
  const deliveredAt = formatDeliveredAt(deliveredAtValue(gift));
  return templates.giftDelivered({giftId, recipientName: gift.recipientName, deliveredAt});
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
    ...(normalizeEmail(gift.senderEmail) ? {sourceRecipientField: "senderEmail"} :
      normalizeEmail(gift.email) ? {sourceRecipientField: "email"} : {}),
    senderCategory: "gifts",
    recipientRole: "sender",
    tags: [{name: "product", value: "gifts"}, {name: "event", value: "gift_delivered"}],
    extra: {
      giftId: text(giftId),
      recipientId: senderId,
      preheader: message.preheader,
      heading: message.heading,
      ctaLabel: message.ctaLabel,
      ctaUrl: message.ctaUrl,
      templateId: message.templateId,
    },
  }, db.collection("emailQueue"));
  return notificationId;
}

module.exports.normalizeEmail = normalizeEmail;
module.exports.giftDeliveryEmail = giftDeliveryEmail;
module.exports.emailNotificationId = emailNotificationId;
module.exports.queueGiftDeliveryEmail = queueGiftDeliveryEmail;
