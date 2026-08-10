/* eslint-disable max-len, require-jsdoc */
const functions = require("firebase-functions/v1");
const {FieldValue, getFirestore} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");
const {createHash} = require("node:crypto");

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
const contactFieldPattern = /(phone|phonenumber|mobile|contactnumber|tel|userphone|riderphone|senderphone|driverphone|courierphone)/i;
const privateNotificationFieldPattern = /(fcm|push.?token|notification.?token|stripe|payment|checkout|client.?secret|billing|secure.*url|story.*token|gift.*message|recipient.*(?:email|phone|name)|medical|medication|prescription|diagnosis|audit)/i;
const privateIdentifierPattern = /\b(?:sk|pk|rk)_(?:live|test)_[A-Za-z0-9_-]+\b|\b(?:pi|pm|ch|seti|src|tok|cs_(?:live|test))_[A-Za-z0-9_-]+\b|\beyJ[A-Za-z0-9_-]{40,}(?:\.[A-Za-z0-9_-]+){1,2}\b|\b[A-Za-z0-9_-]{40,}:[A-Za-z0-9_-]{20,}\b/gi;
const sensitiveQueryPattern = /((?:[?&]|\b)(?:token|secret|client_secret|payment_intent)\s*=\s*)[^&\s]+/gi;
const messageMutationIdPattern = /^[A-Za-z0-9._:-]{8,180}$/;
const maxNotificationAttempts = 5;
const retryDelaysMinutes = [1, 5, 15, 60, 240];
const permanentPushErrors = new Set([
  "messaging/invalid-registration-token",
  "messaging/registration-token-not-registered",
  "messaging/invalid-argument",
]);

function maskContactDetails(value) {
  return clean(value)
      .replace(emailPattern, "[email removed]")
      .replace(phonePattern, "[phone number removed]")
      .replace(privateIdentifierPattern, "[private reference removed]")
      .replace(sensitiveQueryPattern, "$1[private value removed]");
}

function redactContactFields(value) {
  if (Array.isArray(value)) return value.map((item) => redactContactFields(item));
  if (!value || typeof value !== "object") {
    return typeof value === "string" ? maskContactDetails(value) : value;
  }
  return Object.fromEntries(Object.entries(value).flatMap(([key, item]) => {
    if (contactFieldPattern.test(key) || privateNotificationFieldPattern.test(key)) return [];
    return [[key, redactContactFields(item)]];
  }));
}

function notificationIdFor({recipientId = "", recipientRole = "", type = "", correlationId = ""}) {
  const authority = [recipientRole, recipientId, type, correlationId].map(clean).join("|");
  return `notification_${createHash("sha256").update(authority).digest("hex").slice(0, 40)}`;
}

function notificationCorrelationFor(type, data = {}) {
  const explicit = clean(data.correlationId);
  if (explicit) return explicit;
  const authority = [
    data.eventId,
    data.deliveryId,
    data.bookingId,
    data.requestId,
    data.giftId,
    data.healthPickupId,
    data.pickupId,
    data.businessId,
    data.transactionId,
    data.adjustmentId,
    data.ticketId,
    data.announcementId,
    data.status,
    data.stage,
    data.action,
    data.amount,
  ].map(clean).filter(Boolean);
  if (!authority.length) {
    throw new functions.https.HttpsError(
        "failed-precondition",
        "Notification event identity is required.",
    );
  }
  return `${clean(type) || "system"}:${authority.join(":")}`;
}

function messageDocumentId(chatId, senderId, clientMessageId) {
  const authority = [chatId, senderId, clientMessageId].map(clean).join("|");
  return `message_${createHash("sha256").update(authority).digest("hex").slice(0, 40)}`;
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

async function profileTokens(uid, role) {
  if (!uid) return [];
  const db = getFirestore();
  const deviceTokens = await db.collection("notificationTokens")
      .where("uid", "==", uid).limit(20).get();
  const tokens = [...new Set(deviceTokens.docs
      .filter((doc) => doc.data().active === true)
      .map((doc) => clean(doc.data().token)).filter(Boolean))];
  if (!deviceTokens.empty) return tokens;
  const collections = role === "rider" ? ["riderProfiles", "riders"] : ["users", "senders"];
  for (const collection of collections) {
    const doc = await db.collection(collection).doc(uid).get();
    if (!doc.exists) continue;
    const token = clean(doc.data().fcmToken || doc.data().pushToken);
    if (token) return [token];
  }
  return [];
}

function retryState(attempts, errorCode, now = Date.now()) {
  const permanent = permanentPushErrors.has(clean(errorCode));
  if (permanent || attempts >= maxNotificationAttempts) {
    return {status: "exhausted", retryable: false, nextRetryAt: null, permanent};
  }
  const delay = retryDelaysMinutes[Math.min(attempts, retryDelaysMinutes.length - 1)];
  return {status: "failed", retryable: true, nextRetryAt: new Date(now + delay * 60000), permanent: false};
}

async function sendPushToTokens(tokens, payload) {
  if (!tokens.length) return {successCount: 0, failureCount: 0, responses: []};
  return getMessaging().sendEachForMulticast({...payload, tokens});
}

async function participantDisplayName(uid, role, context) {
  if (!uid) return "Participant";
  const token = context.auth && context.auth.uid === uid ? context.auth.token || {} : {};
  const tokenName = clean(token.name);
  if (tokenName) return tokenName;
  if (role === "admin") return "Circum Support";
  if (uid === "circum-support") return "Circum Support";
  const db = getFirestore();
  const collections = role === "rider" ? ["riderProfiles", "riders"] : ["users", "senders"];
  for (const collection of collections) {
    const doc = await db.collection(collection).doc(uid).get();
    if (!doc.exists) continue;
    const data = doc.data() || {};
    const name = clean(data.fullName || data.displayName || data.name);
    if (name) return name;
  }
  return role === "rider" ? "Rider" : "Sender";
}

async function emitNotification({recipientId, recipientRole = "sender", type, title, body, data = {}}) {
  const db = getFirestore();
  const safeData = redactContactFields(data);
  const destination = destinationFor(type, safeData);
  const correlationId = notificationCorrelationFor(type, safeData);
  const ref = db.collection("notifications").doc(notificationIdFor({
    recipientId,
    recipientRole,
    type,
    correlationId,
  }));
  const payload = {
    notificationId: ref.id,
    correlationId,
    recipientId: recipientId || null,
    recipientRole,
    type: clean(type) || "system",
    title: maskContactDetails(title) || "Circum update",
    body: maskContactDetails(body),
    message: maskContactDetails(body),
    category: notificationCategory(type, data.category),
    data: {...safeData, destination},
    destination,
    read: false,
    archived: false,
    deliveryStatus: "persisted",
    deliveryState: "persisted",
    pushDeliveryStatus: "pending",
    deliveryAttempts: 0,
    retryCount: 0,
    retryable: false,
    pushProvider: "fcm",
    createdAt: FieldValue.serverTimestamp(),
  };
  let shouldSend = true;
  await db.runTransaction(async (transaction) => {
    const existing = await transaction.get(ref);
    if (existing.exists) {
      shouldSend = false;
      return;
    }
    transaction.set(ref, payload);
  });
  if (!shouldSend) return ref.id;
  const tokens = await profileTokens(recipientId, recipientRole);
  if (!tokens.length) {
    await ref.set({
      deliveryStatus: "persisted",
      failureReason: "push_token_missing",
      retryable: false,
      pushDeliveryStatus: "exhausted",
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  } else {
    await sendPushToTokens(tokens, {
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
    }).then((result) => {
      if (!result.successCount) {
        const error = result.responses.find((item) => item.error)?.error;
        throw error || new Error("push_failed");
      }
      return ref.set({
      pushDeliveryStatus: "sent",
      deliveryStatus: "sent",
      deliveryState: "sent",
      pushDeviceSuccessCount: result.successCount,
      pushDeviceFailureCount: result.failureCount,
      deliveryAttempts: FieldValue.increment(1),
      retryCount: FieldValue.increment(1),
      lastDeliveryAttemptAt: FieldValue.serverTimestamp(),
      sentAt: FieldValue.serverTimestamp(),
      retryable: false,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    }).catch((error) => {
      const state = retryState(1, error && error.code);
      return ref.set({
      pushDeliveryStatus: state.status,
      deliveryStatus: "failed",
      deliveryState: "failed",
      failureReason: clean(error && (error.code || error.message)) || "push_failed",
      deliveryAttempts: FieldValue.increment(1),
      retryCount: FieldValue.increment(1),
      lastDeliveryAttemptAt: FieldValue.serverTimestamp(),
      retryable: state.retryable,
      nextRetryAt: state.nextRetryAt,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    });
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
  const initialSenderName = await participantDisplayName(
      customerId,
      participantRole,
      {},
  );
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
      lastMessage: maskContactDetails(data.lastMessage || data.message),
    }, {merge: true});
    transaction.set(ticketRef, {
      chatId,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    const initialText = maskContactDetails(data.message);
    if (initialText) {
      transaction.set(chatRef.collection("messages").doc("ticket_initial"), {
        threadId: chatId,
        ticketId,
        senderId: customerId || "support-guest",
        senderName: initialSenderName,
        senderDisplayName: initialSenderName,
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
  if (chat.readOnly === true) return false;
  if (admin) return true;
  return Array.isArray(chat.participants) && chat.participants.includes(senderId);
}

async function sendMessage(data, context) {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Sign in to send a message.");
  const senderId = context.auth.uid;
  const chatId = clean(data.chatId || data.requestId || data.bookingId);
  const message = maskContactDetails(data.message || data.messageText);
  const messageType = clean(data.messageType || "text").toLowerCase();
  const clientMessageId = clean(data.clientMessageId || data.correlationId);
  if (!chatId || !message) {
    throw new functions.https.HttpsError("invalid-argument", "A conversation and message are required.");
  }
  if (!messageMutationIdPattern.test(clientMessageId)) {
    throw new functions.https.HttpsError("invalid-argument", "A valid message mutation id is required.");
  }
  if (!allowedMessageTypes.has(messageType) || messageType === "system") {
    throw new functions.https.HttpsError("invalid-argument", "Unsupported message type.");
  }
  if (message.length > 2000) throw new functions.https.HttpsError("invalid-argument", "Messages are limited to 2000 characters.");
  if (Array.isArray(data.attachments) && data.attachments.length) {
    throw new functions.https.HttpsError("invalid-argument", "Message attachments are not supported.");
  }

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
  const messageRef = chatRef.collection("messages").doc(messageDocumentId(chatId, senderId, clientMessageId));
  const correlationId = `${chatId}:${senderId}:${clientMessageId}`;
  const senderRole = isAdmin(context) ? "admin" : recipientRoleFor(chat, senderId);
  const senderName = await participantDisplayName(senderId, senderRole, context);
  let duplicate = false;
  await db.runTransaction(async (transaction) => {
    const [latestChat, existingMessage] = await Promise.all([
      transaction.get(chatRef),
      transaction.get(messageRef),
    ]);
    if (existingMessage.exists) {
      duplicate = true;
      return;
    }
    if (!latestChat.exists || !canSend(latestChat.data(), senderId, isAdmin(context))) {
      throw new functions.https.HttpsError("permission-denied", "Conversation access denied.");
    }
    transaction.set(messageRef, {
      messageId: messageRef.id,
      conversationId: chatId,
      correlationId,
      senderId,
      senderName,
      senderDisplayName: senderName,
      recipientIds,
      senderRole,
      messageText: message,
      message,
      messageType,
      readBy: [senderId],
      createdAt: FieldValue.serverTimestamp(),
      status: "sent",
      deliveryState: "persisted",
      retryCount: 0,
      notificationId: null,
      audited: true,
      clientMessageId,
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
  return {ok: true, chatId, messageId: messageRef.id, duplicate};
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
  const reportMutationId = clean(data.reportMutationId || data.correlationId);
  if (!chatId || !messageId || !reason) throw new functions.https.HttpsError("invalid-argument", "A message and reason are required.");
  if (!messageMutationIdPattern.test(reportMutationId)) {
    throw new functions.https.HttpsError("invalid-argument", "A valid report mutation id is required.");
  }
  const db = getFirestore();
  const chat = await db.collection("chats").doc(chatId).get();
  if (!chat.exists || (!isAdmin(context) && !(chat.data().participants || []).includes(context.auth.uid))) {
    throw new functions.https.HttpsError("permission-denied", "Conversation access denied.");
  }
  const message = await chat.ref.collection("messages").doc(messageId).get();
  if (!message.exists) {
    throw new functions.https.HttpsError("not-found", "Message not found in this conversation.");
  }
  const reportId = `report_${createHash("sha256").update([chatId, messageId, context.auth.uid].join("|")).digest("hex").slice(0, 40)}`;
  const report = db.collection("messageReports").doc(reportId);
  await report.create({
    reportId,
    chatId,
    messageId,
    reporterId: context.auth.uid,
    reason: reason.slice(0, 500),
    deliveryId: clean(chat.data().deliveryId || chat.data().bookingId),
    createdAt: FieldValue.serverTimestamp(),
    status: "open",
  }).catch((error) => {
    if (!(error && (error.code === 6 || error.code === "already-exists"))) throw error;
  });
  return {ok: true, reportId};
}

async function sendAnnouncement(data, context) {
  if (!context.auth || !isAdmin(context)) throw new functions.https.HttpsError("permission-denied", "Admin access is required.");
  const title = clean(data.title);
  const body = clean(data.body);
  const audience = clean(data.audience || "everyone").toLowerCase();
  const announcementId = clean(data.announcementId);
  if (!title || !body) throw new functions.https.HttpsError("invalid-argument", "A title and message are required.");
  if (!messageMutationIdPattern.test(announcementId)) {
    throw new functions.https.HttpsError("invalid-argument", "A valid announcement mutation id is required.");
  }
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
    if (users) recipients.push(...users.docs.map((doc) => ({id: doc.id, role: "sender"})));
    if (riders) recipients.push(...riders.docs.map((doc) => ({id: doc.id, role: "rider"})));
  }
  const notificationIds = await Promise.all(recipients.map((recipient) => emitNotification({
    recipientId: recipient.id,
    recipientRole: recipient.role,
    type: "system_announcement",
    title,
    body,
    data: {
      category: "system",
      announcement: true,
      announcementId,
      correlationId: `announcement:${announcementId}`,
    },
  })));
  await db.collection("adminAuditLogs").doc().set({
    adminUserId: context.auth.uid,
    actionType: "platform_announcement_sent",
    recordType: "notifications",
    recordId: announcementId,
    newValue: {audience, recipientCount: recipients.length, notificationIds},
    reason: "Announcement sent through backend notification engine",
    createdAt: FieldValue.serverTimestamp(),
  });
  return {ok: true, recipientCount: recipients.length, notificationIds};
}

async function claimNotificationRetry(db, notificationId) {
  const ref = db.collection("notifications").doc(notificationId);
  let notification = null;
  await db.runTransaction(async (transaction) => {
    const snap = await transaction.get(ref);
    if (!snap.exists) throw new functions.https.HttpsError("not-found", "Notification not found.");
    const current = snap.data() || {};
    const status = clean(current.pushDeliveryStatus).toLowerCase();
    if (status === "sent" || status === "retrying" || current.retryable !== true) {
      throw new functions.https.HttpsError("failed-precondition", "Notification is not eligible for retry.");
    }
    notification = current;
    transaction.set(ref, {
      pushDeliveryStatus: "retrying",
      retryable: false,
      lastRetriedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  });
  return notification;
}

async function retryNotificationDelivery(data, context) {
  if (!context.auth || !isAdmin(context)) throw new functions.https.HttpsError("permission-denied", "Admin access is required.");
  const notificationId = clean(data.notificationId);
  if (!notificationId) throw new functions.https.HttpsError("invalid-argument", "A notification id is required.");
  const db = getFirestore();
  const ref = db.collection("notifications").doc(notificationId);
  const notification = await claimNotificationRetry(db, notificationId);
  const tokens = await profileTokens(clean(notification.recipientId), clean(notification.recipientRole));
  if (!tokens.length) {
    await ref.set({
      deliveryStatus: "persisted",
      failureReason: "push_token_missing",
      retryable: false,
      pushDeliveryStatus: "exhausted",
      lastRetriedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    throw new functions.https.HttpsError("failed-precondition", "Recipient has no push token.");
  }
  const destination = notification.destination || {};
  try {
    const result = await sendPushToTokens(tokens, {
      notification: {
        title: clean(notification.title) || "Circum update",
        body: clean(notification.body || notification.message),
      },
      data: {
        type: clean(notification.type) || "system",
        notificationId,
        route: clean(destination.route) || "notifications",
        bookingId: clean(destination.bookingId),
        chatId: clean(destination.chatId),
        giftId: clean(destination.giftId),
        healthPickupId: clean(destination.healthPickupId),
        businessId: clean(destination.businessId),
      },
    });
    if (!result.successCount) {
      const failure = result.responses.find((item) => item.error)?.error;
      throw failure || new Error("push_failed");
    }
    await ref.set({
      pushDeliveryStatus: "sent",
      deliveryStatus: "sent",
      pushDeviceSuccessCount: result.successCount,
      pushDeviceFailureCount: result.failureCount,
      deliveryAttempts: FieldValue.increment(1),
      lastRetriedAt: FieldValue.serverTimestamp(),
      sentAt: FieldValue.serverTimestamp(),
      retryable: false,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    await db.collection("adminAuditLogs").doc().set({
      adminUserId: context.auth.uid,
      actionType: "notification_retry_sent",
      recordType: "notifications",
      recordId: notificationId,
      reason: "Notification push retry sent through backend",
      createdAt: FieldValue.serverTimestamp(),
    });
    return {ok: true, notificationId, status: "sent"};
  } catch (error) {
    const reason = clean(error && (error.code || error.message)) || "push_failed";
    const attempts = Number(notification.deliveryAttempts || 0) + 1;
    const state = retryState(attempts, error && error.code);
    await ref.set({
      pushDeliveryStatus: state.status,
      deliveryStatus: "failed",
      failureReason: reason,
      deliveryAttempts: FieldValue.increment(1),
      lastRetriedAt: FieldValue.serverTimestamp(),
      retryable: state.retryable,
      nextRetryAt: state.nextRetryAt,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    await db.collection("adminAuditLogs").doc().set({
      adminUserId: context.auth.uid,
      actionType: "notification_retry_failed",
      recordType: "notifications",
      recordId: notificationId,
      reason,
      createdAt: FieldValue.serverTimestamp(),
    });
    throw new functions.https.HttpsError("internal", "Notification retry failed.");
  }
}

async function processNotificationRetries() {
  const db = getFirestore();
  const due = await db.collection("notifications")
      .where("retryable", "==", true).where("nextRetryAt", "<=", new Date()).limit(100).get();
  let sent = 0;
  let exhausted = 0;
  for (const doc of due.docs) {
    try {
      const notification = await claimNotificationRetry(db, doc.id);
      const tokens = await profileTokens(clean(notification.recipientId), clean(notification.recipientRole));
      const attempts = Number(notification.deliveryAttempts || 0) + 1;
      if (!tokens.length) {
        await doc.ref.set({pushDeliveryStatus: "exhausted", retryable: false,
          failureReason: "push_token_missing", deliveryAttempts: attempts,
          updatedAt: FieldValue.serverTimestamp()}, {merge: true});
        exhausted++;
        continue;
      }
      const destination = notification.destination || {};
      const result = await sendPushToTokens(tokens, {
        notification: {title: clean(notification.title) || "Circum update",
          body: clean(notification.body || notification.message)},
        data: {type: clean(notification.type) || "system", notificationId: doc.id,
          route: clean(destination.route) || "notifications"},
      });
      if (!result.successCount) throw result.responses.find((item) => item.error)?.error || new Error("push_failed");
      await doc.ref.set({pushDeliveryStatus: "sent", deliveryStatus: "sent", retryable: false,
        deliveryAttempts: attempts, pushDeviceSuccessCount: result.successCount,
        pushDeviceFailureCount: result.failureCount, sentAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp()}, {merge: true});
      sent++;
    } catch (error) {
      const current = await doc.ref.get();
      const attempts = Number((current.data() || {}).deliveryAttempts || 0) + 1;
      const state = retryState(attempts, error && error.code);
      await doc.ref.set({pushDeliveryStatus: state.status, retryable: state.retryable,
        nextRetryAt: state.nextRetryAt, deliveryAttempts: attempts,
        failureReason: clean(error && (error.code || error.message)) || "push_failed",
        updatedAt: FieldValue.serverTimestamp()}, {merge: true});
      if (!state.retryable) exhausted++;
    }
  }
  return {processed: due.size, sent, exhausted};
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
  const initialMessage = maskContactDetails(data.initialMessage).slice(0, 4000);
  const closeImmediately = data.closeImmediately === true;
  const participantRole = clean(data.participantRole || "sender").toLowerCase() === "rider" ? "rider" : "sender";
  const token = context.auth.token || {};
  const submittedBy = {
    uid,
    role: participantRole,
    email: clean(token.email).toLowerCase() || null,
    displayName: clean(token.name || data.displayName).slice(0, 120) || null,
  };
  const db = getFirestore();
  const ticketId = clean(data.ticketId);
  if (ticketId && isAdmin(context)) {
    const result = await ensureSupportConversationForTicket(db, ticketId);
    return {ok: true, ...result};
  }
  if (!closeImmediately) {
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
  }

  const ticketRef = db.collection("supportTickets").doc();
  const chatId = `support_${ticketRef.id}`;
  const chatRef = db.collection("chats").doc(chatId);
  const status = closeImmediately ? "closed" : "open";
  await db.runTransaction(async (transaction) => {
    transaction.set(ticketRef, {
      channel: "sender_in_app_chat",
      status,
      priority: "normal",
      type: topic,
      topic,
      title,
      message: initialMessage,
      lastMessage: initialMessage,
      adminUnreadCount: initialMessage ? 1 : 0,
      chatId,
      userId: uid,
      senderId: participantRole === "sender" ? uid : null,
      riderId: participantRole === "rider" ? uid : null,
      submittedBy,
      closedBy: closeImmediately ? "system" : null,
      closedReason: closeImmediately ? "one_way_submission" : null,
      closedAt: closeImmediately ? FieldValue.serverTimestamp() : null,
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
      status,
      readOnly: closeImmediately,
      source: "communication-engine",
      submittedBy,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      closedAt: closeImmediately ? FieldValue.serverTimestamp() : null,
      closedReason: closeImmediately ? "one_way_submission" : null,
      lastMessage: initialMessage,
    });
    if (initialMessage) {
      transaction.set(chatRef.collection("messages").doc("ticket_initial"), {
        senderId: uid,
        senderRole: participantRole,
        senderType: participantRole,
        senderName: submittedBy.displayName,
        messageText: initialMessage,
        message: initialMessage,
        messageType: "text",
        initialSupportRequest: true,
        closedSubmission: closeImmediately,
        readBy: [uid],
        createdAt: FieldValue.serverTimestamp(),
        status: "sent",
        audited: true,
      });
    }
  });
  return {ok: true, chatId, ticketId: ticketRef.id, existing: false, status};
}

async function submitWebsiteSupportRequest(data, context) {
  const message = maskContactDetails(data.message).slice(0, 4000);
  const email = clean(data.email).slice(0, 180).toLowerCase();
  if (!message || !email || !email.includes("@")) {
    throw new functions.https.HttpsError("invalid-argument", "Contact email and message are required.");
  }
  const db = getFirestore();
  const uid = context.auth ? context.auth.uid : null;
  const ticketRef = db.collection("supportTickets").doc();
  const chatId = `support_${ticketRef.id}`;
  const chatRef = db.collection("chats").doc(chatId);
  const now = FieldValue.serverTimestamp();
  const participantRole = clean(data.participantRole || "sender").toLowerCase() === "rider" ? "rider" : "sender";
  const name = clean(data.name || data.displayName).slice(0, 160);

  await db.runTransaction(async (transaction) => {
    transaction.set(ticketRef, {
      channel: "web_live_chat",
      status: "open",
      priority: "normal",
      name,
      email,
      message,
      lastMessage: message,
      lastMessageAt: now,
      adminUnreadCount: 1,
      pageUrl: clean(data.pageUrl).slice(0, 2048),
      chatId,
      userId: uid,
      source: "submitWebsiteSupportRequest",
      createdAt: now,
      updatedAt: now,
    });
    if (!uid) return;
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
      status: "open",
      source: "communication-engine",
      createdAt: now,
      updatedAt: now,
      lastMessage: message,
    }, {merge: true});
    transaction.set(chatRef.collection("messages").doc("ticket_initial"), {
      threadId: chatId,
      ticketId: ticketRef.id,
      senderId: uid,
      senderRole: participantRole,
      senderType: participantRole,
      senderName: name || null,
      messageText: message,
      message,
      attachments: [],
      initialSupportRequest: true,
      readBy: [uid],
      createdAt: now,
      status: "sent",
      audited: true,
    });
  });

  return {ok: true, ticketId: ticketRef.id, chatId};
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
exports.notificationIdFor = notificationIdFor;
exports.notificationCorrelationFor = notificationCorrelationFor;
exports.redactContactFields = redactContactFields;
exports.maskContactDetails = maskContactDetails;
exports.messageDocumentId = messageDocumentId;
exports.claimNotificationRetry = claimNotificationRetry;
exports.retryState = retryState;
exports.processNotificationRetriesHandler = processNotificationRetries;
exports._sendCircumMessageHandler = sendMessage;
const protectedCallable = functions.runWith({enforceAppCheck: true}).https;
exports.sendCircumMessage = protectedCallable.onCall(sendMessage);
exports.startAdminConversation = protectedCallable.onCall(startAdminConversation);
exports.getOrCreateSupportConversation = protectedCallable.onCall(getOrCreateSupportConversation);
exports.submitWebsiteSupportRequest = protectedCallable.onCall(submitWebsiteSupportRequest);
exports.updateSupportConversationStatus = protectedCallable.onCall(updateSupportConversationStatus);
exports.markConversationRead = protectedCallable.onCall(markConversationRead);
exports.setConversationTyping = protectedCallable.onCall(setConversationTyping);
exports.reportCircumMessage = protectedCallable.onCall(reportMessage);
exports.sendCircumAnnouncement = protectedCallable.onCall(sendAnnouncement);
exports.retryNotificationDelivery = protectedCallable.onCall(retryNotificationDelivery);
exports.processNotificationRetries = functions.pubsub.schedule("every 5 minutes")
    .timeZone("Europe/London").onRun(processNotificationRetries);
exports.closeDeliveryConversation = async (deliveryId, status) => {
  if (!terminalDeliveryStatuses.has(clean(status).toLowerCase())) return;
  await getFirestore().collection("chats").doc(clean(deliveryId)).set({
    readOnly: true,
    closedAt: FieldValue.serverTimestamp(),
    closedReason: clean(status),
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
};
exports.appendSystemMessage = async (deliveryId, message, eventId) => {
  const db = getFirestore();
  const chatRef = db.collection("chats").doc(clean(deliveryId));
  const chat = await chatRef.get();
  if (!chat.exists) return;
  const safeMessage = maskContactDetails(message);
  const correlationId = clean(eventId) || `${clean(deliveryId)}:${safeMessage}`;
  const messageRef = chatRef.collection("messages").doc(notificationIdFor({
    recipientId: clean(deliveryId),
    recipientRole: "system",
    type: "chat_system_message",
    correlationId,
  }));
  await db.runTransaction(async (transaction) => {
    const existing = await transaction.get(messageRef);
    if (existing.exists) return;
    transaction.set(messageRef, {
      senderId: "circum-system",
      senderRole: "system",
      correlationId,
      messageText: safeMessage,
      message: safeMessage,
      messageType: "system",
      readBy: [],
      createdAt: FieldValue.serverTimestamp(),
      status: "sent",
      audited: true,
    });
  });
};
