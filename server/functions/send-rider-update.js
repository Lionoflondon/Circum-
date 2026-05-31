const functions = require("firebase-functions/v1");
const {getMessaging} = require("firebase-admin/messaging");

const sendRiderUpdate = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
        "unauthenticated",
        "User must be authenticated to send rider updates.",
    );
  }

  const {token, data: messageData, message, title} = data;

  if (!token || !messageData || !messageData.type) {
    throw new functions.https.HttpsError(
        "invalid-argument",
        "Must provide token and data.type.",
    );
  }

  const payload = {
    data: Object.fromEntries(
        Object.entries(messageData).map(([key, value]) => [key, String(value)]),
    ),
    android: {
      priority: "high",
      ttl: 5000,
    },
    apns: {
      headers: {
        "apns-priority": "10",
        "apns-push-type": "background",
      },
      payload: {
        aps: {
          "content-available": 1,
        },
      },
    },
    token,
  };

  if (title || message) {
    payload.notification = {
      title: title || "Circum",
      body: message || "",
    };
  }

  const messageId = await getMessaging().send(payload);
  return {success: true, messageId};
});

module.exports = sendRiderUpdate;
