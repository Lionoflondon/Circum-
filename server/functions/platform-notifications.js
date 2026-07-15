/* eslint-disable max-len, require-jsdoc */
const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue, Timestamp} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");
const {riderMatchesIris} = require("./iris-core");
const communicationEngine = require("./communication-engine");

const text = (value) => `${value || ""}`.trim();
const openStatuses = new Set(["requested", "pending", "broadcast", "broadcasted", "awaiting_rider", "finding_rider"]);
const giftEvents = new Set([
  "gift_draft_saved",
  "gift_submitted",
  "payment_succeeded",
  "payment_failed",
  "subscription_created",
  "subscription_cancelled",
  "campaign_waiting_for_match",
  "campaign_match_found",
  "campaign_match_confirmed",
  "gift_approved",
  "gift_rejected",
  "curation_started",
  "ready_for_gift_delivery",
  "delivery_started",
  "rider_assigned",
  "gift_delivered",
  "story_locked",
  "story_unlocked",
  "story_manually_locked",
  "story_manually_unlocked",
  "issue_raised",
  "dispute_opened",
  "dispute_resolved",
]);

async function profileToken(uid, role) {
  if (!uid) return "";
  const db = getFirestore();
  const collections = role === "rider" ? ["riderProfiles", "riders"] : ["users", "senders"];
  for (const collection of collections) {
    const doc = await db.collection(collection).doc(uid).get();
    if (doc.exists) {
      const data = doc.data();
      const token = text(data.fcmToken || data.pushToken || data.code);
      if (token) return token;
    }
  }
  return "";
}

async function adminRecipients() {
  const snapshot = await getFirestore().collection("adminUsers").get();
  return snapshot.docs.filter((doc) => text(doc.data().status || "active").toLowerCase() !== "disabled").map((doc) => ({
    uid: doc.id,
    token: text(doc.data().fcmToken || doc.data().pushToken),
  }));
}

async function notify({recipientId, recipientRole, type, title, body, bookingId, ticketId, data = {}}) {
  if (recipientRole !== "admin") {
    return communicationEngine.emitNotification({
      recipientId,
      recipientRole: recipientRole === "shipper" ? "sender" : recipientRole,
      type,
      title,
      body,
      data: {...data, bookingId, ticketId},
    });
  }
  const db = getFirestore();
  const ref = db.collection("notifications").doc();
  await ref.set({
    recipientId: recipientId || null,
    recipientRole,
    type,
    title,
    message: body,
    bookingId: bookingId || null,
    ticketId: ticketId || null,
    data,
    read: false,
    createdAt: FieldValue.serverTimestamp(),
  });

  let token = "";
  if (recipientRole === "admin") {
    const admins = await adminRecipients();
    const tokens = admins.map((admin) => admin.token).filter(Boolean);
    if (tokens.length) {
      await getMessaging().sendEachForMulticast({
        tokens,
        notification: {title, body},
        data: {type, notificationId: ref.id, bookingId: bookingId || "", ticketId: ticketId || ""},
      }).catch((error) => console.error("Admin notification failed", error));
    }
    return ref.id;
  }
  token = await profileToken(recipientId, recipientRole);
  if (token) {
    await getMessaging().send({
      token,
      notification: {title, body},
      data: {type, notificationId: ref.id, bookingId: bookingId || "", ticketId: ticketId || ""},
    }).catch((error) => console.error("Notification failed", error));
  }
  return ref.id;
}

function giftNotificationRecord({
  notificationId = "",
  userId,
  email = "",
  giftId,
  giftType,
  eventType,
  title,
  body,
  channel = "in_app",
  deliveryStatus = "pending",
  createdAt = FieldValue.serverTimestamp(),
  sentAt = null,
  failureReason = "",
}) {
  if (!giftEvents.has(eventType)) {
    throw new Error(`Unsupported Gifts notification event: ${eventType}`);
  }
  const channelName = text(channel) || "in_app";
  const configured = channelName === "in_app" ||
    (channelName === "email" && text(process.env.GIFTS_EMAIL_PROVIDER)) ||
    (channelName === "push" && text(process.env.FCM_SERVER_KEY || process.env.GOOGLE_APPLICATION_CREDENTIALS));
  const finalStatus = channelName === "in_app" ? deliveryStatus : configured ? deliveryStatus : "skipped";
  const skippedReason = configured ? failureReason : `${channelName}_not_configured`;
  return {
    notificationId: notificationId || `${giftId}_${eventType}_${channelName}`,
    userId,
    email: text(email).toLowerCase(),
    giftId,
    giftType,
    eventType,
    title,
    body,
    channel: channelName,
    deliveryStatus: finalStatus,
    createdAt,
    sentAt: sentAt || null,
    failureReason: finalStatus === "skipped" || failureReason ? skippedReason : null,
  };
}

function giftNotificationRecordsForTransition({
  userId,
  email = "",
  giftId,
  giftType,
  eventType,
  title,
  body,
  channels = ["in_app", "email", "push"],
  createdAt = FieldValue.serverTimestamp(),
}) {
  return channels.map((channel) => giftNotificationRecord({
    userId,
    email,
    giftId,
    giftType,
    eventType,
    title,
    body,
    channel,
    createdAt,
  }));
}

function deliveryIds(data) {
  return {
    bookingId: text(data.requestId || data.bookingId || data.id),
    senderId: text(data.senderId || data.userId || data.customerId),
    riderId: text(data.riderId || data.driverId || data.assignedRiderId || data.assignedDriverId),
  };
}

function deliverySystemMessage(status) {
  return {
    accepted: "Rider accepted the delivery.",
    navigating_to_pickup: "Rider is heading to pickup.",
    arrived: "Rider has arrived.",
    arrived_at_pickup: "Rider has arrived.",
    pickup_verified: "Pickup completed.",
    collected: "Delivery started.",
    picked_up: "Delivery started.",
    navigating_to_dropoff: "Delivery is in progress.",
    pin_required: "Recipient PIN verification is required.",
    sender_no_show_pickup: "Pickup was marked as missed after the collection wait.",
    delivered: "Delivery completed.",
    completed: "Delivery completed.",
  }[text(status).toLowerCase()] || null;
}

function isBackendSystemMessage(message = {}) {
  return text(message.senderId) === "circum-system" ||
    text(message.senderRole).toLowerCase() === "system" ||
    text(message.messageType).toLowerCase() === "system";
}

function moneyText(value, currency = "GBP") {
  const amount = Number(value || 0);
  if (!Number.isFinite(amount) || amount <= 0) return "";
  const prefix = text(currency).toUpperCase() === "GBP" ? "£" : `${text(currency).toUpperCase()} `;
  return `${prefix}${amount.toFixed(2)}`;
}

function giftStatus(data = {}) {
  return text(data.status || data.giftStatus || data.flowStatus || data.campaignStatus).toLowerCase();
}

function giftStatusNotification(status) {
  const normalized = text(status).toLowerCase();
  const map = {
    submitted_for_review: ["gift_submitted", "Gift submitted", "Your gift request has been sent to the Circum team."],
    waiting_for_match: ["campaign_waiting_for_match", "Gift match requested", "We are looking for a compatible gift match."],
    paid_waiting_for_match: ["campaign_waiting_for_match", "Gift match requested", "We are looking for a compatible gift match."],
    approved: ["gift_approved", "Gift approved", "Your gift request has been approved."],
    rejected: ["gift_rejected", "Gift update", "Your gift request needs attention."],
    curation_started: ["curation_started", "Gift curation started", "The Circum team has started preparing your gift."],
    ready_for_gift_delivery: ["ready_for_gift_delivery", "Gift ready for delivery", "Your gift is ready for delivery."],
    delivered: ["gift_delivered", "Gift delivered", "Your gift has been delivered."],
  };
  return map[normalized] || null;
}

async function notifyGiftStatus({before = {}, after = {}, giftId}) {
  const oldStatus = giftStatus(before);
  const nextStatus = giftStatus(after);
  if (!nextStatus || oldStatus === nextStatus) return null;
  const copy = giftStatusNotification(nextStatus);
  if (!copy) return null;
  const senderId = text(after.senderId || after.userId || after.uid);
  if (!senderId) return null;
  return notify({
    recipientId: senderId,
    recipientRole: "shipper",
    type: copy[0],
    title: copy[1],
    body: copy[2],
    bookingId: text(after.deliveryId || after.requestId || giftId),
    data: {
      category: "Gifts",
      giftId,
      giftType: text(after.giftType || after.type || "gift"),
    },
  });
}

function customerWaitingCharge(data) {
  const waiting = data.waiting || {};
  const financial = data.noShowFinancial || {};
  return {
    amount: financial.amount || waiting.noShowFeeAmount || data.waitingCharge || data.waitingChargeAmount || data.pickupNoShowSurchargeGbp,
    currency: financial.currency || waiting.currency || data.currency || "GBP",
  };
}

exports.onDeliveryCreated = functions.firestore.document("deliveryRequests/{deliveryId}").onCreate(async (snapshot) => {
  const delivery = snapshot.data();
  const ids = deliveryIds({...delivery, id: snapshot.id});
  if (ids.senderId) await notify({recipientId: ids.senderId, recipientRole: "shipper", type: "delivery_created", title: "Delivery created", body: "Your delivery request has been created.", bookingId: ids.bookingId, data: {category: "Deliveries"}});
  const riders = await getFirestore().collection("riderProfiles").get();
  const eligible = riders.docs.filter((doc) => {
    const rider = doc.data();
    const approval = text(rider.approvalStatus || rider.verificationStatus).toLowerCase();
    const online = text(rider.status || rider.availabilityStatus).toLowerCase();
    return ["approved", "verified"].includes(approval) &&
      ["online", "available"].includes(online) &&
      riderMatchesIris(rider, delivery);
  });
  await Promise.all(eligible.map((doc) => notify({
    recipientId: doc.id,
    recipientRole: "rider",
    type: "new_delivery",
    title: "New delivery available",
    body: "A delivery matching your vehicle is ready to review.",
    bookingId: ids.bookingId,
  })));
  const highValue = delivery.vanguardEnabled === true || Number(delivery.declaredValue || 0) > 250;
  if (highValue) await notify({recipientRole: "admin", type: "high_value_delivery", title: "High-value delivery created", body: "A Vanguard or high-value delivery needs visibility.", bookingId: ids.bookingId});
});

exports.onDeliveryUpdated = functions.firestore.document("deliveryRequests/{deliveryId}").onUpdate(async (change) => {
  const before = change.before.data();
  const after = change.after.data();
  const oldStatus = text(before.status || before.deliveryStatus).toLowerCase();
  const status = text(after.status || after.deliveryStatus).toLowerCase();
  const statusChanged = status && status !== oldStatus;
  const ids = deliveryIds({...after, id: change.after.id});
  const oldPayment = text(before.paymentStatus || before.paymentState).toLowerCase();
  const payment = text(after.paymentStatus || after.paymentState).toLowerCase();
  const oldWaitingContext = text(before.waitingContextState).toLowerCase();
  const waitingContext = text(after.waitingContextState).toLowerCase();
  const oldWaitingCharge = Number(customerWaitingCharge(before).amount || 0);
  const waitingCharge = customerWaitingCharge(after);
  const waitingChargeAmount = Number(waitingCharge.amount || 0);
  if (!statusChanged && oldPayment === payment && oldWaitingContext === waitingContext && oldWaitingCharge === waitingChargeAmount) return;
  if (statusChanged) {
    await communicationEngine.closeDeliveryConversation(ids.bookingId, status);
  }
  const systemMessage = statusChanged ? deliverySystemMessage(status) : null;
  if (systemMessage) {
    await communicationEngine.appendSystemMessage(ids.bookingId, systemMessage);
  }
  const chargeText = moneyText(waitingCharge.amount, waitingCharge.currency);
  const senderMessages = {
    accepted: ["Rider accepted", "A rider has accepted your delivery.", "Deliveries"],
    finding_rider: ["Searching for rider", "Circum is searching for an eligible rider.", "Deliveries"],
    awaiting_rider: ["Searching for rider", "Circum is searching for an eligible rider.", "Deliveries"],
    navigating_to_pickup: ["Rider en route", "Your rider is on the way to the pickup.", "Deliveries"],
    arrived: ["Rider arrived", "Your rider has arrived at the pickup.", "Deliveries"],
    arrived_at_pickup: ["Rider waiting", "Your rider has arrived. Free waiting has started.", "Deliveries"],
    rider_arrived_pickup: ["Waiting timer started", "Your Circum rider has arrived at the pickup address.", "Deliveries"],
    sender_no_show_pickup: ["No-show", `Pickup was marked as no-show after the waiting period.${chargeText ? ` Additional waiting charge: ${chargeText}.` : ""}`, "Deliveries"],
    pickup_verified: ["Pickup confirmed", "Your rider has verified pickup.", "Deliveries"],
    collected: ["Delivery in progress", "Your parcel has been collected.", "Deliveries"],
    picked_up: ["Delivery in progress", "Your parcel has been collected.", "Deliveries"],
    navigating_to_dropoff: ["Delivery in progress", "Your parcel is on the way to drop-off.", "Deliveries"],
    arrived_at_dropoff: ["Near destination", "Your rider is arriving at the drop-off.", "Deliveries"],
    pin_required: ["Receiver PIN needed", "The receiver PIN is needed to complete handover.", "Deliveries"],
    delivered: ["Delivered", "Your parcel has been delivered.", "Deliveries"],
    completed: ["Delivered", "Your delivery is complete.", "Deliveries"],
    cancelled: ["Delivery cancelled", "Your delivery has been cancelled.", "Deliveries"],
    issue_reported: ["Delivery issue reported", "Your rider reported an issue. Circum support can review it.", "Support"],
    refunded: ["Refund issued", "Your delivery refund has been updated.", "Payments"],
  };
  const senderMessage = statusChanged ? senderMessages[status] : null;
  if (ids.senderId && senderMessage) await notify({recipientId: ids.senderId, recipientRole: "shipper", type: `delivery_${status}`, title: senderMessage[0], body: senderMessage[1], bookingId: ids.bookingId, data: {category: senderMessage[2]}});
  if (ids.senderId && oldPayment !== payment && ["paid", "succeeded", "success"].includes(payment)) await notify({recipientId: ids.senderId, recipientRole: "shipper", type: "payment_successful", title: "Payment successful", body: "Your delivery payment was successful.", bookingId: ids.bookingId, data: {category: "Payments"}});
  if (ids.senderId && oldPayment !== payment && ["failed", "declined"].includes(payment)) await notify({recipientId: ids.senderId, recipientRole: "shipper", type: "payment_failed", title: "Payment failed", body: "Your delivery payment was not completed.", bookingId: ids.bookingId, data: {category: "Payments"}});
  if (ids.senderId && oldWaitingContext !== waitingContext && waitingContext === "customer_responded") await notify({recipientId: ids.senderId, recipientRole: "shipper", type: "customer_responded", title: "Customer response received", body: "Waiting continues under the current policy.", bookingId: ids.bookingId, data: {category: "Deliveries"}});
  if (ids.senderId && oldWaitingCharge !== waitingChargeAmount && waitingChargeAmount > 0) await notify({recipientId: ids.senderId, recipientRole: "shipper", type: "waiting_charge_updated", title: "Waiting charge updated", body: `Additional waiting charge: ${moneyText(waitingCharge.amount, waitingCharge.currency)}.`, bookingId: ids.bookingId, data: {category: "Payments"}});
  if (ids.riderId && statusChanged && (status.includes("cancel") || status === "updated")) await notify({recipientId: ids.riderId, recipientRole: "rider", type: status.includes("cancel") ? "delivery_cancelled" : "delivery_updated", title: status.includes("cancel") ? "Delivery cancelled" : "Delivery updated", body: status.includes("cancel") ? "A delivery assigned to you was cancelled." : "An assigned delivery has been updated.", bookingId: ids.bookingId});
});

exports.onGiftRequestCreated = functions.firestore.document("giftRequests/{giftId}").onCreate((snapshot, context) =>
  notifyGiftStatus({after: snapshot.data(), giftId: context.params.giftId}));

exports.onGiftRequestUpdated = functions.firestore.document("giftRequests/{giftId}").onUpdate((change, context) =>
  notifyGiftStatus({before: change.before.data(), after: change.after.data(), giftId: context.params.giftId}));

exports.onGiftCampaignParticipantUpdated = functions.firestore.document("giftCampaignParticipants/{participantId}").onUpdate((change, context) =>
  notifyGiftStatus({before: change.before.data(), after: change.after.data(), giftId: context.params.participantId}));

exports.onChatMessageCreated = functions.firestore.document("chats/{chatId}/messages/{messageId}").onCreate(async (snapshot, context) => {
  const message = snapshot.data();
  if (isBackendSystemMessage(message)) return;
  const chat = await getFirestore().collection("chats").doc(context.params.chatId).get();
  if (!chat.exists) return;
  const chatData = chat.data();
  const senderId = text(message.senderId);
  const participants = Array.isArray(chatData.participants) ? chatData.participants : [];
  const roles = chatData.participantRoles || {};
  const bookingId = text(chatData.bookingId || chatData.requestId);
  const ticketId = text(chatData.ticketId);
  await Promise.all(participants.filter((uid) => uid && uid !== senderId && uid !== "circum-support").map((uid) => notify({
    recipientId: uid,
    recipientRole: roles[uid] === "rider" ? "rider" : "shipper",
    type: "chat_message",
    title: "New chat message",
    body: text(message.messageText || message.message) || "You have a new message.",
    bookingId,
    ticketId,
  })));
  if (message.initialSupportRequest !== true && text(message.senderRole) !== "admin" && (chatData.type === "support" || participants.includes("circum-support"))) await notify({recipientRole: "admin", type: "admin_response_needed", title: "New support message", body: "A shipper or rider sent a new message.", bookingId, ticketId});
});

exports.onSupportTicketCreated = functions.firestore.document("supportTickets/{ticketId}").onCreate((snapshot) => notify({recipientRole: "admin", type: "support_ticket", title: "New support ticket", body: text(snapshot.data().message) || "A new support request was opened.", ticketId: snapshot.id}));
exports.onDisputeCreated = functions.firestore.document("disputes/{disputeId}").onCreate((snapshot) => notify({recipientRole: "admin", type: "dispute", title: "New dispute", body: "A delivery dispute needs review.", bookingId: text(snapshot.data().bookingId || snapshot.data().requestId)}));

exports.onRiderProfileUpdated = functions.firestore.document("riderProfiles/{riderId}").onUpdate(async (change, context) => {
  const before = text(change.before.data().approvalStatus || change.before.data().verificationStatus);
  const after = text(change.after.data().approvalStatus || change.after.data().verificationStatus);
  if (!after || before === after) return;
  if (["approved", "verified", "rejected"].includes(after.toLowerCase())) await notify({recipientId: context.params.riderId, recipientRole: "rider", type: "verification_update", title: after.toLowerCase() === "rejected" ? "Verification update" : "Verification approved", body: after.toLowerCase() === "rejected" ? "Your rider verification needs attention." : "Your rider account has been approved."});
});

exports.onPayoutUpdated = functions.firestore.document("payoutRequests/{requestId}").onUpdate(async (change) => {
  const before = text(change.before.data().status).toLowerCase();
  const after = text(change.after.data().status).toLowerCase();
  if (before === after || !["paid", "approved", "rejected"].includes(after)) return;
  const data = change.after.data();
  await notify({recipientId: text(data.riderId), recipientRole: "rider", type: "earnings_update", title: after === "paid" ? "Earnings paid" : "Withdrawal updated", body: `Your withdrawal is ${after}.`});
});

exports.escalateUnclaimedDeliveries = functions.pubsub.schedule("every 1 minutes").onRun(async () => {
  const db = getFirestore();
  const cutoff = Timestamp.fromMillis(Date.now() - 2 * 60 * 1000);
  const snapshot = await db.collection("deliveryRequests").where("createdAt", "<=", cutoff).limit(100).get();
  for (const doc of snapshot.docs) {
    const delivery = doc.data();
    if (!openStatuses.has(text(delivery.status).toLowerCase())) continue;
    const createdAt = delivery.createdAt && delivery.createdAt.toMillis ? delivery.createdAt.toMillis() : Date.now();
    const ageMinutes = Math.floor((Date.now() - createdAt) / 60000);
    const stage = ageMinutes >= 5 ? 5 : ageMinutes >= 4 ? 4 : ageMinutes >= 3 ? 3 : ageMinutes >= 2 ? 2 : 0;
    if (!stage || Number(delivery.notificationEscalationStage || 0) >= stage) continue;
    if (stage === 5) {
      await notify({recipientRole: "admin", type: "unclaimed_delivery", title: "Unclaimed delivery", body: "A delivery remains unclaimed after five minutes.", bookingId: text(delivery.requestId || doc.id)});
    } else {
      const riders = await db.collection("riderProfiles").get();
      await Promise.all(riders.docs.filter((riderDoc) => {
        const rider = riderDoc.data();
        const approval = text(rider.approvalStatus || rider.verificationStatus).toLowerCase();
        const online = text(rider.status || rider.availabilityStatus).toLowerCase();
        return ["approved", "verified"].includes(approval) &&
          ["online", "available"].includes(online) &&
          riderMatchesIris(rider, delivery);
      }).map((rider) => notify({recipientId: rider.id, recipientRole: "rider", type: "delivery_reminder", title: "Delivery still available", body: "An eligible delivery is still waiting for a rider.", bookingId: text(delivery.requestId || doc.id)})));
    }
    await doc.ref.set({notificationEscalationStage: stage, notificationEscalatedAt: FieldValue.serverTimestamp()}, {merge: true});
  }
  return null;
});

exports.giftNotificationRecord = giftNotificationRecord;
exports.giftNotificationRecordsForTransition = giftNotificationRecordsForTransition;
exports._private = {
  deliverySystemMessage,
  isBackendSystemMessage,
  giftStatus,
  giftStatusNotification,
};
