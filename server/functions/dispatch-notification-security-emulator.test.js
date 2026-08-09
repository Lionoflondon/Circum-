/* eslint-disable max-len */
const test = require("node:test");
const assert = require("node:assert/strict");
const {getApps, initializeApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const acceptRideRequests = require("./accept-ride-requests");
const sendRiderUpdate = require("./send-rider-update");
const communicationEngine = require("./communication-engine");

const emulator = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
const suite = emulator ? test : test.skip;
const prefix = `dispatch_security_${Date.now()}`;

function approvedRider(vehicleType = "car") {
  return {
    approvalStatus: "approved",
    verificationStatus: "verified",
    onboardingStatus: "approved",
    dispatchEligible: true,
    documentsVerified: true,
    vehicleVerified: true,
    accountStatus: "active",
    vehicleType,
    fullName: "Eligible Rider",
  };
}

function healthyPresence(riderId, now = Date.now()) {
  return {
    riderId,
    isOnline: true,
    availabilityStatus: "available",
    busy: false,
    dispatchEligible: true,
    lastHeartbeatAt: now,
    gpsStatus: "active",
    currentLocation: {
      latitude: 51.5007,
      longitude: -0.1246,
      accuracyMeters: 10,
      updatedAt: now,
    },
  };
}

if (emulator && getApps().length === 0) initializeApp({projectId: "circum-dispatch-security-test"});

suite("two concurrent Rider acceptances produce exactly one assignment", async () => {
  const db = getFirestore();
  const deliveryId = `${prefix}_race`;
  const senderId = `${prefix}_sender`;
  const riders = [`${prefix}_rider_a`, `${prefix}_rider_b`];
  const batch = db.batch();
  for (const riderId of riders) {
    batch.set(db.collection("riders").doc(riderId), approvedRider());
    batch.set(db.collection("riderProfiles").doc(riderId), approvedRider());
    batch.set(db.collection("riderPresence").doc(riderId), healthyPresence(riderId));
  }
  batch.set(db.collection("deliveryRequests").doc(deliveryId), {
    requestId: deliveryId,
    senderId,
    status: "requested",
    deliveryStatus: "requested",
    matchingStatus: "available",
    dispatchStatus: "requested",
    paymentStatus: "paid",
    packageDescription: "Documents",
    requiredVehicle: "car",
    workflow: "Standard",
    pickupPosition: {geopoint: {latitude: 51.501, longitude: -0.125}},
  });
  batch.set(db.collection("chats").doc(deliveryId), {
    conversationType: "sender_rider",
    participants: [senderId, `${prefix}_former_rider`, "circum-support"],
    participantRoles: {[senderId]: "sender", [`${prefix}_former_rider`]: "rider", "circum-support": "admin"},
  });
  await batch.commit();

  const results = await Promise.allSettled(riders.map((riderId) =>
    acceptRideRequests._private.acceptRideRequestHandler(
        {requestId: deliveryId},
        {auth: {uid: riderId, token: {}}},
        {db, notifySender: async () => true},
    )));
  assert.equal(results.filter((result) => result.status === "fulfilled").length, 1);
  assert.equal(results.filter((result) => result.status === "rejected").length, 1);
  const delivery = (await db.collection("deliveryRequests").doc(deliveryId).get()).data();
  assert.equal(delivery.status, "accepted");
  assert.ok(riders.includes(delivery.riderId));
  const winnerPresence = (await db.collection("riderPresence").doc(delivery.riderId).get()).data();
  assert.equal(winnerPresence.busy, true);
  assert.equal(winnerPresence.activeDeliveryId, deliveryId);
  const loser = riders.find((riderId) => riderId !== delivery.riderId);
  assert.equal((await db.collection("riderPresence").doc(loser).get()).data().busy, false);
  const chat = (await db.collection("chats").doc(deliveryId).get()).data();
  assert.deepEqual(chat.participants, [senderId, delivery.riderId, "circum-support"]);
  assert.equal(chat.participants.includes(`${prefix}_former_rider`), false);
  assert.equal(chat.participantRoles[senderId], "sender");
  assert.equal(chat.participantRoles[delivery.riderId], "rider");
});

suite("deterministic notification correlation persists and attempts one event once", async () => {
  const db = getFirestore();
  const recipientId = `${prefix}_notification_recipient`;
  const correlationId = `${prefix}:same-event`;
  const input = {
    recipientId,
    recipientRole: "sender",
    type: "delivery_update",
    title: "Delivery updated",
    body: "Your delivery changed.",
    data: {
      deliveryId: `${prefix}_delivery`,
      correlationId,
      fcmToken: "must-not-persist",
      stripeCheckoutSessionId: "must-not-persist",
    },
  };
  const [first, second] = await Promise.all([
    communicationEngine.emitNotification(input),
    communicationEngine.emitNotification(input),
  ]);
  assert.equal(first, second);
  const snapshot = await db.collection("notifications").where("correlationId", "==", correlationId).get();
  assert.equal(snapshot.size, 1);
  const stored = snapshot.docs[0].data();
  assert.equal("fcmToken" in stored.data, false);
  assert.equal("stripeCheckoutSessionId" in stored.data, false);
  assert.equal(stored.deliveryAttempts, 0);
});

suite("concurrent notification retries have exactly one Firestore claim owner", async () => {
  const db = getFirestore();
  const notificationId = `${prefix}_retry_notification`;
  await db.collection("notifications").doc(notificationId).set({
    recipientId: `${prefix}_retry_recipient`,
    recipientRole: "sender",
    pushDeliveryStatus: "failed",
    retryable: true,
  });
  const claims = await Promise.allSettled([
    communicationEngine.claimNotificationRetry(db, notificationId),
    communicationEngine.claimNotificationRetry(db, notificationId),
  ]);
  assert.equal(claims.filter((claim) => claim.status === "fulfilled").length, 1);
  assert.equal(claims.filter((claim) => claim.status === "rejected").length, 1);
  const stored = (await db.collection("notifications").doc(notificationId).get()).data();
  assert.equal(stored.pushDeliveryStatus, "retrying");
  assert.equal(stored.retryable, false);
});

suite("sendRiderUpdate rejects arbitrary tokens and wrong recipients", async () => {
  const db = getFirestore();
  const deliveryId = `${prefix}_notify_delivery`;
  const riderId = `${prefix}_notify_rider`;
  const ownerId = `${prefix}_notify_sender`;
  await db.collection("deliveryRequests").doc(deliveryId).set({
    requestId: deliveryId,
    senderId: ownerId,
    riderId,
    status: "accepted",
  });
  await db.collection("users").doc(ownerId).set({fcmToken: "authoritative-token"});
  const context = {auth: {uid: riderId, token: {}}};
  await assert.rejects(
      sendRiderUpdate._private.handler({deliveryId, token: "attacker-token", data: {status: "accepted"}}, context, {db}),
      (error) => error.code === "permission-denied",
  );
  await assert.rejects(
      sendRiderUpdate._private.handler({deliveryId, recipientId: "another-user", data: {status: "accepted"}}, context, {db}),
      (error) => error.code === "permission-denied",
  );
  let emitted = null;
  const result = await sendRiderUpdate._private.handler({deliveryId, data: {status: "accepted"}}, context, {
    db,
    emitNotification: async (payload) => {
      emitted = payload;
      return "notification-safe";
    },
  });
  assert.equal(result.notificationId, "notification-safe");
  assert.equal(emitted.recipientId, ownerId);
  assert.equal(JSON.stringify(emitted).includes("authoritative-token"), false);
});

suite("chat messages remain confined to declared participants", async () => {
  const db = getFirestore();
  const chatId = `${prefix}_chat`;
  const senderId = `${prefix}_chat_sender`;
  const riderId = `${prefix}_chat_rider`;
  await db.collection("chats").doc(chatId).set({
    conversationType: "sender_rider",
    participants: [senderId, riderId],
    participantRoles: {[senderId]: "sender", [riderId]: "rider"},
    bookingId: `${prefix}_chat_delivery`,
  });
  await assert.rejects(
      communicationEngine._sendCircumMessageHandler(
          {chatId, message: "private", clientMessageId: `${prefix}_outsider`},
          {auth: {uid: "outsider", token: {}}},
      ),
      (error) => error.code === "permission-denied",
  );
  await assert.rejects(
      communicationEngine._sendCircumMessageHandler(
          {chatId: `${prefix}_forged_chat`, message: "private", clientMessageId: `${prefix}_forged`},
          {auth: {uid: senderId, token: {}}},
      ),
      (error) => error.code === "not-found",
  );
  await assert.rejects(
      communicationEngine._sendCircumMessageHandler(
          {chatId, message: "missing identity"},
          {auth: {uid: senderId, token: {}}},
      ),
      (error) => error.code === "invalid-argument",
  );
  const result = await communicationEngine._sendCircumMessageHandler(
      {chatId, message: "Delivery update", clientMessageId: `${prefix}_message`},
      {auth: {uid: senderId, token: {name: "Sender"}}},
  );
  const replay = await communicationEngine._sendCircumMessageHandler(
      {chatId, message: "Delivery update", clientMessageId: `${prefix}_message`},
      {auth: {uid: senderId, token: {name: "Sender"}}},
  );
  const message = (await db.collection("chats").doc(chatId).collection("messages").doc(result.messageId).get()).data();
  const messages = await db.collection("chats").doc(chatId).collection("messages").get();
  assert.deepEqual(message.recipientIds, [riderId]);
  assert.equal(message.recipientIds.includes("outsider"), false);
  assert.equal(replay.messageId, result.messageId);
  assert.equal(replay.duplicate, true);
  assert.equal(messages.size, 1);
  const privateResult = await communicationEngine._sendCircumMessageHandler(
      {chatId, message: "Email me at sender@example.com about pi_secret", clientMessageId: `${prefix}_private_message`},
      {auth: {uid: senderId, token: {name: "Sender"}}},
  );
  const privateMessage = (await db.collection("chats").doc(chatId)
      .collection("messages").doc(privateResult.messageId).get()).data();
  assert.doesNotMatch(privateMessage.message, /sender@example\.com|pi_secret/);
  await assert.rejects(
      communicationEngine._sendCircumMessageHandler(
          {chatId, message: "unsafe", clientMessageId: `${prefix}_attachment`, attachments: [{url: "https://example.invalid"}]},
          {auth: {uid: senderId, token: {name: "Sender"}}},
      ),
      (error) => error.code === "invalid-argument",
  );
  await db.collection("chats").doc(chatId).set({readOnly: true}, {merge: true});
  await assert.rejects(
      communicationEngine._sendCircumMessageHandler(
          {chatId, message: "late sender message", clientMessageId: `${prefix}_closed_sender`},
          {auth: {uid: senderId, token: {}}},
      ),
      (error) => error.code === "permission-denied",
  );
  await assert.rejects(
      communicationEngine._sendCircumMessageHandler(
          {chatId, message: "late admin message", clientMessageId: `${prefix}_closed_admin`},
          {auth: {uid: "admin", token: {admin: true}}},
      ),
      (error) => error.code === "permission-denied",
  );
});
