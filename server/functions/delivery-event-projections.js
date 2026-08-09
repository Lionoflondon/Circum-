/* eslint-disable max-len, require-jsdoc */
"use strict";

const functions = require("firebase-functions/v1");
const {getFirestore, Timestamp} = require("firebase-admin/firestore");
const {appendOperationalEvent} = require("./delivery-operational-events");

function clean(value) {
  return `${value || ""}`.trim();
}

function eventTimestamp(context) {
  return Timestamp.fromDate(new Date(context.timestamp));
}

function deliveryIdFrom(data = {}) {
  return clean(data.deliveryId || data.bookingId || data.requestId);
}

exports.onNotificationOperationalWrite = functions.firestore
    .document("notifications/{notificationId}").onWrite(async (change, context) => {
      if (!change.after.exists) return null;
      const before = change.before.exists ? change.before.data() || {} : null;
      const after = change.after.data() || {};
      const deliveryId = deliveryIdFrom({...after, ...(after.data || {})});
      if (!deliveryId) return null;
      let eventType = null;
      if (!before) eventType = "NotificationCreated";
      else {
        const previous = clean(before.pushDeliveryStatus || before.deliveryStatus).toLowerCase();
        const current = clean(after.pushDeliveryStatus || after.deliveryStatus).toLowerCase();
        if (current !== previous && ["delivered", "sent"].includes(current)) eventType = "NotificationDelivered";
        if (current !== previous && ["failed", "error"].includes(current)) eventType = "NotificationFailed";
      }
      if (!eventType) return null;
      return appendOperationalEvent(getFirestore(), {
        deliveryId,
        eventType,
        correlationId: context.params.notificationId,
        timestamp: eventTimestamp(context),
        actorType: "system",
        source: "notifications.onWrite",
        metadata: {notificationId: context.params.notificationId, type: after.type, recipientRole: after.recipientRole, deliveryStatus: after.deliveryStatus, pushDeliveryStatus: after.pushDeliveryStatus},
      });
    });

exports.onChatOperationalCreate = functions.firestore
    .document("chats/{chatId}").onCreate(async (snapshot, context) => {
      const data = snapshot.data() || {};
      const deliveryId = deliveryIdFrom(data) || (data.conversationType === "sender_rider" ? context.params.chatId : "");
      if (!deliveryId) return null;
      return appendOperationalEvent(getFirestore(), {deliveryId, eventType: "ChatOpened", correlationId: context.params.chatId, timestamp: eventTimestamp(context), actorType: "system", source: "chats.onCreate", metadata: {chatId: context.params.chatId, conversationType: data.conversationType}});
    });

exports.onChatMessageOperationalCreate = functions.firestore
    .document("chats/{chatId}/messages/{messageId}").onCreate(async (snapshot, context) => {
      const db = getFirestore();
      const chat = await db.collection("chats").doc(context.params.chatId).get();
      if (!chat.exists) return null;
      const chatData = chat.data() || {};
      const deliveryId = deliveryIdFrom(chatData) || (chatData.conversationType === "sender_rider" ? context.params.chatId : "");
      if (!deliveryId) return null;
      const data = snapshot.data() || {};
      return appendOperationalEvent(db, {deliveryId, eventType: "ChatMessageSent", correlationId: context.params.messageId, timestamp: eventTimestamp(context), actorType: data.senderRole || "system", actorId: data.senderId || null, source: "chatMessages.onCreate", metadata: {chatId: context.params.chatId, messageId: context.params.messageId, messageType: data.messageType, status: data.status}});
    });

exports.onDeliveryEvidenceOperationalWrite = functions.firestore
    .document("deliveryEvidence/{deliveryId}/photos/{photoId}").onWrite(async (change, context) => {
      if (!change.after.exists) return null;
      const before = change.before.exists ? change.before.data() || {} : {};
      const data = change.after.data() || {};
      if (data.verified !== true || before.verified === true) return null;
      return appendOperationalEvent(getFirestore(), {deliveryId: context.params.deliveryId, eventType: "EvidenceUploaded", correlationId: context.params.photoId, timestamp: eventTimestamp(context), actorType: "rider", actorId: data.riderId || data.actorUid || null, source: "deliveryEvidence.photos.onCreate", metadata: {photoId: context.params.photoId, evidenceType: data.evidenceType || data.type, verified: data.verified === true}});
    });

module.exports.deliveryIdFrom = deliveryIdFrom;
