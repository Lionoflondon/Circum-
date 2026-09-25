/* eslint-disable max-len, require-jsdoc */
const {getFirestore} = require("firebase-admin/firestore");
const {enqueueEmail, emailQueueId, normalizeEmail: normalizeQueueEmail} = require("./email-queue");
const templates = require("./transactional-email-templates");

const text = (value) => `${value || ""}`.trim();

function normalizeEmail(value) {
  return normalizeQueueEmail(value);
}

function giftDeliveryEmail({giftId, gift = {}}) {
  const token = text(gift.giftStoryAccessToken);
  if (!token || gift.giftStoryUnlocked !== true || text(gift.giftStoryStatus) !== "unlocked") return null;
  return templates.giftDelivered({recipientName: gift.recipientName,
    storyUrl: `https://circumuk.com/story/${encodeURIComponent(token)}`});
}

function emailNotificationId(giftId, eventType) {
  return emailQueueId(["gift", giftId, eventType]);
}

async function queueGiftDeliveryEmail({giftId, gift = {}, db = getFirestore()}) {
  const email = normalizeEmail(gift.senderEmail);
  const senderId = text(gift.senderId || gift.userId);
  if (!email || !giftId || text(gift.status || gift.giftStatus) !== "delivered") return null;
  const notificationId = emailNotificationId(giftId, "gift_delivered");
  const message = giftDeliveryEmail({giftId, gift});
  if (!message) return null;
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
    senderCategory: "gifts",
    recipientRole: "sender",
    tags: [{name: "product", value: "gifts"}, {name: "event", value: "gift_delivered"}],
    extra: {
      sourceRecipientField: "senderEmail",
      sourceRequiredFields: {giftStoryStatus: "unlocked", giftStoryUnlocked: true},
      sourceStoryRole: "sender",
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
