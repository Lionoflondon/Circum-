/* eslint-disable max-len, require-jsdoc */
const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue, Timestamp} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");
const {riderMatchesIris} = require("./iris-core");

const text = (value) => `${value || ""}`.trim();
const openStatuses = new Set(["requested", "pending", "broadcast", "broadcasted", "awaiting_rider", "finding_rider"]);

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

function deliveryIds(data) {
  return {
    bookingId: text(data.requestId || data.bookingId || data.id),
    senderId: text(data.senderId || data.userId || data.customerId),
    riderId: text(data.riderId || data.driverId || data.assignedRiderId || data.assignedDriverId),
  };
}

exports.onDeliveryCreated = functions.firestore.document("deliveryRequests/{deliveryId}").onCreate(async (snapshot) => {
  const delivery = snapshot.data();
  const ids = deliveryIds({...delivery, id: snapshot.id});
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
  if (!status || status === oldStatus) return;
  const ids = deliveryIds({...after, id: change.after.id});
  const senderMessages = {
    accepted: ["Rider accepted", "A rider has accepted your delivery."],
    arrived: ["Rider arrived", "Your rider has arrived at the pickup."],
    arrived_at_pickup: ["Rider arrived", "Your rider has arrived at the pickup."],
    collected: ["Parcel collected", "Your parcel has been collected."],
    picked_up: ["Parcel collected", "Your parcel has been collected."],
    delivered: ["Parcel delivered", "Your parcel has been delivered."],
    completed: ["Parcel delivered", "Your delivery is complete."],
    refunded: ["Refund updated", "Your delivery refund has been updated."],
  };
  const senderMessage = senderMessages[status];
  if (ids.senderId && senderMessage) await notify({recipientId: ids.senderId, recipientRole: "shipper", type: `delivery_${status}`, title: senderMessage[0], body: senderMessage[1], bookingId: ids.bookingId});
  if (ids.riderId && (status.includes("cancel") || status === "updated")) await notify({recipientId: ids.riderId, recipientRole: "rider", type: status.includes("cancel") ? "delivery_cancelled" : "delivery_updated", title: status.includes("cancel") ? "Delivery cancelled" : "Delivery updated", body: status.includes("cancel") ? "A delivery assigned to you was cancelled." : "An assigned delivery has been updated.", bookingId: ids.bookingId});
});

exports.onChatMessageCreated = functions.firestore.document("chats/{chatId}/messages/{messageId}").onCreate(async (snapshot, context) => {
  const message = snapshot.data();
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
