const functions = require("firebase-functions/v1");

const sendRiderUpdate = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
        "unauthenticated",
        "User must be authenticated to send rider updates.",
    );
  }

  throw new functions.https.HttpsError(
      "failed-precondition",
      "Legacy direct-token Rider notifications are disabled. Use an authorised server-owned notification path.",
  );
});

module.exports = sendRiderUpdate;
