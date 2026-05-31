const functions = require("firebase-functions/v1");
const {getFirestore} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");

const sendMessage = functions.https.onCall(async (data, context) => {
  try {
    // Check authentication
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated",
          "User must be authenticated to send messages.");
    }

    // Validate input data
    const {recipientId, message, requestId} = data;
    if (!recipientId || !message || !requestId) {
      throw new functions.https.HttpsError("invalid-argument",
          "Must provide recipientId, message, and requestId");
    }

    const senderId = context.auth.uid;
    const timestamp = new Date();

    // Determine if sender is rider or user by checking collections
    const [riderDoc, userDoc] = await Promise.all([
      getFirestore().collection("riders").doc(senderId).get(),
      getFirestore().collection("users").doc(senderId).get(),
    ]);

    const senderType = riderDoc.exists ? "rider" : "user";
    const recipientType = senderType === "rider" ? "user" : "rider";

    // Get recipient's FCM token
    const recipientDoc = await getFirestore()
        .collection(recipientType + "s")
        .doc(recipientId)
        .get();

    if (!recipientDoc.exists) {
      throw new functions.https.HttpsError("not-found", "Recipient not found");
    }

    const recipientData = recipientDoc.data();
    const fcmToken = recipientData.fcmToken;

    // Create message document
    const messageData = {
      senderId,
      senderType,
      recipientId,
      recipientType,
      message,
      requestId,
      timeStamp: timestamp.toISOString(),
      status: "sent",
    };

    // Store message in Firestore
    const chatRef = getFirestore()
        .collection("chats")
        .doc(requestId)
        .collection("messages");

    const messageRef = await chatRef.add(messageData);

    // Update last message in chat document
    await getFirestore().collection("chats").doc(requestId).set({
      lastMessage: message,
      lastMessageTimestamp: timestamp,
      participants: [senderId, recipientId],
      requestId,
    }, {merge: true});

    // Send push notification if FCM token exists
    if (fcmToken) {
      const senderData = senderType === "rider" ? riderDoc.data() : userDoc.data();
      const senderName = (senderData.name || senderData.username || "Circum")
          .split(" ")[0];

      const notificationMessage = {
        data: {
          type: "message",
          data: JSON.stringify({
            requestId,
            senderName,
            senderId,
            senderType,
            message,
            timeStamp: timestamp.toISOString(),
          }),
        },
        android: {
          priority: "high",
        },
        apns: {
          headers: {
            "apns-priority": "10",
            "apns-push-type": "background",
          },
          payload: {
            aps: {
              sound: "default",
              contentAvailable: true,
            },
          },
        },
        token: fcmToken,
      };

      try {
        await getMessaging().send(notificationMessage);
      } catch (error) {
        console.error("Error sending notification:", error);
      }
    }

    return {
      success: true,
      messageId: messageRef.id,
      timestamp: timestamp.toISOString(),
    };
  } catch (error) {
    console.error("Error in sendMessage:", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
});

module.exports = sendMessage;
