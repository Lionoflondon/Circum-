/* eslint-disable max-len, require-jsdoc */
const functions = require("firebase-functions/v1");
const {FieldValue, getFirestore} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");

const terminalDeliveryStatuses = new Set([
  "delivered", "completed", "cancelled", "canceled", "failed",
  "archived", "archived_stale", "archived_expired", "admin_removed_stale",
]);
const allowedConversationTypes = new Set([
  "sender_rider", "admin_sender", "admin_rider", "support",
]);
const allowedMessageTypes = new Set(["text", "system"]);
const notificationCategories = new Set([
  "deliveries", "wallet", "health", "gifts", "business", "system",
]);
const supportTicketStatuses = new Set(["open", "assigned", "pending", "resolved", "closed"]);

const clean = (value) => `${value || ""}`.trim();
const emailPattern = /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/gi;
const phonePattern = /(?<!\w)(?:\+?\d[\d\s().-]{7,}\d)(?!\w)/g;

function maskContactDetails(value) {
  return clean(value)
      .replace(emailPattern, "[email removed]")
      .replace(phonePattern, "[phone number removed]");
}

function isAdmin(context) {
  const token = context.auth && context.auth.token || {};
  const role = clean(token.role || token.adminRole).toLowerCase();
  const roles = Array.isArray(token.roles) ? token.roles.map((item) => clean(item).toLowerCase()) : [];
  return token.admin === true || token.super_admin === true ||
    [role, ...roles].some((item) => ["super_admin", "operations_admin", "support_agent", "driver_manager"].includes(item));
}

function recipientRoleFor(chat, uid) {
  const role = clean((chat.participantRoles || {})[uid]).toLowerCase();
  if (role === "admin" || role === "support") return "admin";
  return role === "rider" ? "rider" : "sender";
}

function destinationFor(type, data = {}) {
  const bookingId = clean(data.bookingId || data.deliveryId || data.requestId);
  const giftId = clean(data.giftId);
  const healthId = clean(data.healthPickupId || data.pickupId);
  const businessId = clean(data.businessId);
  const chatId = clean(data.chatId);
  if (chatId || type === "chat_message" || type === "admin_message") {
    return {route: "conversation", chatId, bookingId};
  }
  if (type.startsWith("wallet_") || type.startsWith("roth_") || type.startsWith("referral_")) {
    return {route: "wallet"};
  }
  if (type.startsWith("gift_") || giftId) return {route: "gift", giftId};
  if (type.startsWith("health_") || healthId) return {route: "health", healthPickupId: healthId};
  if (type.startsWith("business_") || businessId) return {route: "business", businessId};
  if (bookingId) return {route: "tracking", bookingId};
  return {route: "notifications"};
}

async function profileToken(uid, role) {
  if (!uid) return "";
  const db = getFirestore();
  const collections = role === "rider" ? ["riderProfiles", "riders"] : ["users", "senders"];
  for (const collection of collections) {
    const doc = await db.collection(collection).doc(uid).get();
    if (!doc.exists) continue;
    const token = clean(doc.data().fcmToken || doc.data().pushToken || doc.data().code);
    if (token) return token;
  }
  return "";
}

async function emitNotification({recipientId, recipientRole = "sender", type, title, body, data = {}}) {
  const db = getFirestore();
  const destination = destinationFor(type, data);
  const ref = db.collection("notifications").doc();
  const payload = {
    recipientId: recipientId || null,
    recipientRole,
    type: clean(type) || "system",
    title: clean(title) || "Circum update",
    body: clean(body),
    message: clean(body),
    category: notificationCategory(type, data.category),
    data: {...data, destination},
    destination,
    read: false,
    archived: false,
    createdAt: FieldValue.serverTimestamp(),
  };
  await ref.set(payload);
  const token = await profileToken(recipientId, recipientRole);
  if (token) {
    await getMessaging().send({
      token,
      notification: {title: payload.title, body: payload.body},
      data: {
        type: payload.type,
        notificationId: ref.id,
        route: destination.route || "notifications",
        bookingId: clean(destination.bookingId),
        chatId: clean(destination.chatId),
        giftId: clean(destination.giftId),
        healthPickupId: clean(destination.healthPickupId),
        businessId: clean(destination.businessId),
      },
    }).catch((error) => console.error("Communication push failed", error));
  }
  return ref.id;
}

function notificationCategory(type, requestedCategory) {
  const requested = clean(requestedCategory).toLowerCase();
  if (notificationCategories.has(requested)) return requested;
  const normalized = clean(type).toLowerCase();
  if (normalized.startsWith("delivery_") || normalized === "new_delivery") return "deliveries";
  if (normalized.startsWith("gift_")) return "gifts";
  if (normalized.startsWith("health_")) return "health";
  if (normalized.startsWith("wallet_") || normalized.startsWith("roth_") || normalized.startsWith("referral_")) return "wallet";
  if (normalized.startsWith("business_")) return "business";
  return "system";
}

function conversationId(type, participantId, deliveryId = "") {
  return type === "sender_rider" ? clean(deliveryId) : `${type}_${participantId}_${deliveryId || "general"}`;
}

function supportChatIdFor(ticketId) {
  return `support_${clean(ticketId)}`;
}

async function ensureSupportConversationForTicket(db, ticketId) {
  const ticketRef = db.collection("supportTickets").doc(ticketId);
  const ticket = await ticketRef.get();
  if (!ticket.exists) {
    throw new functions.https.HttpsError("not-found", "Support request not found.");
  }
  const data = ticket.data() || {};
  const customerId = clean(data.userId || data.senderId || data.riderId);
  const participantRole = clean(data.riderId) && clean(data.riderId) === customerId ? "rider" : "sender";
  const chatId = clean(data.chatId) || supportChatIdFor(ticketId);
  const participants = ["circum-support"];
  if (customerId) participants.unshift(customerId);
  const chatRef = db.collection("chats").doc(chatId);
  await db.runTransaction(async (transaction) => {
    transaction.set(chatRef, {
      threadId: chatId,
      conversationType: "support",
      type: "support",
      ticketId,
      participants,
      participantRoles: {
        ...(customerId ? {[customerId]: participantRole} : {}),
        "circum-support": "admin",
      },
      title: clean(data.title || "Circum Support") || "Circum Support",
      status: clean(data.status || "open") === "resolved" ? "resolved" : "open",
      readOnly: clean(data.status || "open") === "closed",
      source: "communication-engine",
      updatedAt: FieldValue.serverTimestamp(),
      createdAt: FieldValue.serverTimestamp(),
      lastMessage: clean(data.lastMessage || data.message),
    }, {merge: true});
    transaction.set(ticketRef, {
      chatId,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    const initialText = clean(data.message);
    if (initialText) {
      transaction.set(chatRef.collection("messages").doc("ticket_initial"), {
        threadId: chatId,
        ticketId,
        senderId: customerId || "support-guest",
        senderRole: participantRole,
        senderType: participantRole,
        messageText: initialText,
        message: initialText,
        attachments: [],
        initialSupportRequest: true,
        readBy: customerId ? [customerId] : [],
        createdAt: data.createdAt || FieldValue.serverTimestamp(),
        status: "sent",
      }, {merge: true});
    }
  });
  return {chatId, ticketId, customerId, existing: Boolean(data.chatId)};
}

function canSend(chat, senderId, admin) {
  if (admin) return true;
  if (chat.readOnly === true) return false;
  return Array.isArray(chat.participants) && chat.participants.includes(senderId);
}

async function sendMessage(data, context) {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Sign in to send a message.");
  const senderId = context.auth.uid;
  const chatId = clean(data.chatId || data.requestId || data.bookingId);
  const message = maskContactDetails(data.message || data.messageText);
  const messageType = clean(data.messageType || "text").toLowerCase();
  if (!chatId || !message) {
    throw new functions.https.HttpsError("invalid-argument", "A conversation and message are required.");
  }
  if (!allowedMessageTypes.has(messageType) || messageType === "system") {
    throw new functions.https.HttpsError("invalid-argument", "Unsupported message type.");
  }
  if (message.length > 2000) throw new functions.https.HttpsError("invalid-argument", "Messages are limited to 2000 characters.");

  const db = getFirestore();
  const chatRef = db.collection("chats").doc(chatId);
  const chatSnapshot = await chatRef.get();
  if (!chatSnapshot.exists) throw new functions.https.HttpsError("not-found", "Conversation is unavailable.");
  const chat = chatSnapshot.data();
  if (!allowedConversationTypes.has(clean(chat.conversationType || "sender_rider"))) {
    throw new functions.https.HttpsError("failed-precondition", "Conversation type is unavailable.");
  }
  if (!canSend(chat, senderId, isAdmin(context))) {
    throw new functions.https.HttpsError("permission-denied", chat.readOnly === true ? "This conversation is read-only." : "You are not part of this conversation.");
  }
  if (messageType === "location" && !clean(chat.deliveryId || chat.bookingId)) {
    throw new functions.https.HttpsError("failed-precondition", "Location sharing is only available for deliveries.");
  }

  const recipientIds = (chat.participants || []).filter((uid) => uid && uid !== senderId);
  const messageRef = chatRef.collection("messages").doc();
  await db.runTransaction(async (transaction) => {
    transaction.set(messageRef, {
      senderId,
      senderRole: isAdmin(context) ? "admin" : recipientRoleFor(chat, senderId),
      messageText: message,
      message,
      messageType,
      readBy: [senderId],
      createdAt: FieldValue.serverTimestamp(),
      status: "sent",
      audited: true,
    });
    transaction.set(chatRef, {
      lastMessage: message,
      lastMessageAt: FieldValue.serverTimestamp(),
      lastMessageSenderId: senderId,
      unreadBy: recipientIds,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    const ticketId = clean(chat.ticketId);
    if (ticketId) {
      transaction.set(db.collection("supportTickets").doc(ticketId), {
        lastMessage: message,
        lastMessageAt: FieldValue.serverTimestamp(),
        adminUnreadCount: isAdmin(context) ? 0 : FieldValue.increment(1),
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    }
  });
  return {ok: true, chatId, messageId: messageRef.id};
}

async function setConversationTyping(data, context) {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Sign in to update typing.");
  const chatId = clean(data.chatId);
  if (!chatId) throw new functions.https.HttpsError("invalid-argument", "A conversation is required.");
  const ref = getFirestore().collection("chats").doc(chatId);
  const chat = await ref.get();
  if (!chat.exists || (!isAdmin(context) && !(chat.data().participants || []).includes(context.auth.uid))) {
    throw new functions.https.HttpsError("permission-denied", "Conversation access denied.");
  }
  if (chat.data().readOnly === true) return {ok: true, readOnly: true};
  await ref.set({
    [`typing.${context.auth.uid}`]: data.typing === true ? Date.now() + 12000 : null,
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  return {ok: true};
}

async function reportMessage(data, context) {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Sign in to report a message.");
  const chatId = clean(data.chatId);
  const messageId = clean(data.messageId);
  const reason = clean(data.reason);
  if (!chatId || !messageId || !reason) throw new functions.https.HttpsError("invalid-argument", "A message and reason are required.");
  const db = getFirestore();
  const chat = await db.collection("chats").doc(chatId).get();
  if (!chat.exists || (!isAdmin(context) && !(chat.data().participants || []).includes(context.auth.uid))) {
    throw new functions.https.HttpsError("permission-denied", "Conversation access denied.");
  }
  const report = await db.collection("messageReports").add({
    chatId,
    messageId,
    reporterId: context.auth.uid,
    reason: reason.slice(0, 500),
    deliveryId: clean(chat.data().deliveryId || chat.data().bookingId),
    createdAt: FieldValue.serverTimestamp(),
    status: "open",
  });
  return {ok: true, reportId: report.id};
}

async function sendAnnouncement(data, context) {
  if (!context.auth || !isAdmin(context)) throw new functions.https.HttpsError("permission-denied", "Admin access is required.");
  const title = clean(data.title);
  const body = clean(data.body);
  const audience = clean(data.audience || "everyone").toLowerCase();
  if (!title || !body) throw new functions.https.HttpsError("invalid-argument", "A title and message are required.");
  if (!["everyone", "senders", "riders", "business", "health", "user"].includes(audience)) {
    throw new functions.https.HttpsError("invalid-argument", "Unsupported announcement audience.");
  }
  const db = getFirestore();
  let recipients = [];
  if (audience === "user") {
    const recipientId = clean(data.recipientId);
    if (!recipientId) throw new functions.https.HttpsError("invalid-argument", "A recipient is required.");
    recipients = [{id: recipientId, role: clean(data.recipientRole) === "rider" ? "rider" : "sender"}];
  } else {
    const [users, riders] = await Promise.all([
      (audience === "riders" ? Promise.resolve(null) : db.collection("users").limit(500).get()),
      (audience === "senders" || audience === "business" || audience === "health" ? Promise.resolve(null) : db.collection("riderProfiles").limit(500).get()),
    ]);
    if (users) recipients.add(...users.docs.map((doc) => ({id: doc.id, role: "sender"})));
    if (riders) recipients.add(...riders.docs.map((doc) => ({id: doc.id, role: "rider"})));
  }
  await Promise.all(recipients.map((recipient) => emitNotification({
    recipientId: recipient.id,
    recipientRole: recipient.role,
    type: "system_announcement",
    title,
    body,
    data: {category: "system", announcement: true},
  })));
  return {ok: true, recipientCount: recipients.length};
}

async function startAdminConversation(data, context) {
  if (!context.auth || !isAdmin(context)) throw new functions.https.HttpsError("permission-denied", "Admin access is required.");
  const participantId = clean(data.participantId);
  const participantRole = clean(data.participantRole).toLowerCase();
  const deliveryId = clean(data.deliveryId || data.bookingId);
  if (!participantId || !["sender", "rider"].includes(participantRole)) {
    throw new functions.https.HttpsError("invalid-argument", "A sender or rider is required.");
  }
  const type = participantRole === "rider" ? "admin_rider" : "admin_sender";
  const chatId = conversationId(type, participantId, deliveryId);
  const db = getFirestore();
  await db.collection("chats").doc(chatId).set({
    conversationType: type,
    participants: [context.auth.uid, participantId],
    participantRoles: {[context.auth.uid]: "admin", [participantId]: participantRole},
    deliveryId: deliveryId || null,
    bookingId: deliveryId || null,
    readOnly: false,
    updatedAt: FieldValue.serverTimestamp(),
    createdAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  return {chatId};
}

async function getOrCreateSupportConversation(data, context) {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Sign in to contact support.");
  const uid = context.auth.uid;
  const topic = clean(data.topic || "support").slice(0, 80) || "support";
  const title = clean(data.title || "Circum Support").slice(0, 120) || "Circum Support";
  const participantRole = clean(data.participantRole || "sender").toLowerCase() === "rider" ? "rider" : "sender";
  const db = getFirestore();
  const ticketId = clean(data.ticketId);
  if (ticketId && isAdmin(context)) {
    const result = await ensureSupportConversationForTicket(db, ticketId);
    return {ok: true, ...result};
  }
  const existing = await db.collection("supportTickets")
      .where("userId", "==", uid)
      .limit(20)
      .get();
  for (const doc of existing.docs) {
    const ticket = doc.data();
    const status = clean(ticket.status || "open").toLowerCase();
    const chatId = clean(ticket.chatId);
    if (chatId && status !== "resolved" && status !== "closed") {
      return {ok: true, chatId, ticketId: doc.id, existing: true};
    }
  }

  const ticketRef = db.collection("supportTickets").doc();
  const chatId = `support_${ticketRef.id}`;
  const chatRef = db.collection("chats").doc(chatId);
  await db.runTransaction(async (transaction) => {
    transaction.set(ticketRef, {
      channel: "sender_in_app_chat",
      status: "open",
      priority: "normal",
      type: topic,
      topic,
      title,
      message: "",
      lastMessage: "",
      adminUnreadCount: 0,
      chatId,
      userId: uid,
      senderId: participantRole === "sender" ? uid : null,
      riderId: participantRole === "rider" ? uid : null,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.set(chatRef, {
      threadId: chatId,
      conversationType: "support",
      type: "support",
      ticketId: ticketRef.id,
      participants: [uid, "circum-support"],
      participantRoles: {
        [uid]: participantRole,
        "circum-support": "admin",
      },
      title,
      status: "open",
      readOnly: false,
      source: "communication-engine",
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      lastMessage: "",
    });
  });
  return {ok: true, chatId, ticketId: ticketRef.id, existing: false};
}

async function updateSupportConversationStatus(data, context) {
  if (!context.auth || !isAdmin(context)) throw new functions.https.HttpsError("permission-denied", "Admin access is required.");
  const ticketId = clean(data.ticketId);
  const status = clean(data.status || "open").toLowerCase();
  if (!ticketId || !supportTicketStatuses.has(status)) {
    throw new functions.https.HttpsError("invalid-argument", "A valid support status is required.");
  }
  const db = getFirestore();
  const {chatId} = await ensureSupportConversationForTicket(db, ticketId);
  await db.runTransaction(async (transaction) => {
    transaction.set(db.collection("supportTickets").doc(ticketId), {
      status,
      assignedTo: clean(data.assignedTo) || null,
      resolutionNote: clean(data.resolutionNote) || null,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    transaction.set(db.collection("chats").doc(chatId), {
      status: status === "resolved" || status === "closed" ? status : "open",
      readOnly: status === "closed",
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  });
  return {ok: true, chatId, ticketId, status};
}

async function markConversationRead(data, context) {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Sign in to update a conversation.");
  const chatId = clean(data.chatId);
  const db = getFirestore();
  const ref = db.collection("chats").doc(chatId);
  const chat = await ref.get();
  if (!chat.exists || (!isAdmin(context) && !(chat.data().participants || []).includes(context.auth.uid))) {
    throw new functions.https.HttpsError("permission-denied", "Conversation access denied.");
  }
  await ref.set({
    [`readAt.${context.auth.uid}`]: FieldValue.serverTimestamp(),
    unreadBy: FieldValue.arrayRemove(context.auth.uid),
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  return {ok: true};
}

exports.emitNotification = emitNotification;
exports.destinationFor = destinationFor;
exports.sendCircumMessage = functions.https.onCall(sendMessage);
exports.startAdminConversation = functions.https.onCall(startAdminConversation);
exports.getOrCreateSupportConversation = functions.https.onCall(getOrCreateSupportConversation);
exports.updateSupportConversationStatus = functions.https.onCall(updateSupportConversationStatus);
exports.markConversationRead = functions.https.onCall(markConversationRead);
exports.setConversationTyping = functions.https.onCall(setConversationTyping);
exports.reportCircumMessage = functions.https.onCall(reportMessage);
exports.sendCircumAnnouncement = functions.https.onCall(sendAnnouncement);
exports.closeDeliveryConversation = async (deliveryId, status) => {
  if (!terminalDeliveryStatuses.has(clean(status).toLowerCase())) return;
  await getFirestore().collection("chats").doc(clean(deliveryId)).set({
    readOnly: true,
    closedAt: FieldValue.serverTimestamp(),
    closedReason: clean(status),
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
};
exports.appendSystemMessage = async (deliveryId, message) => {
  const chatRef = getFirestore().collection("chats").doc(clean(deliveryId));
  const chat = await chatRef.get();
  if (!chat.exists) return;
  await chatRef.collection("messages").add({
    senderId: "circum-system",
    senderRole: "system",
    messageText: clean(message),
    message: clean(message),
    messageType: "system",
    readBy: [],
    createdAt: FieldValue.serverTimestamp(),
    status: "sent",
    audited: true,
  });
};
