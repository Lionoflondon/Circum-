const functions = require("firebase-functions/v1");
const communicationEngine = require("./communication-engine");

const sendMessage = functions.https.onCall(async (data, context) => {
  try {
    const legacyChatId = data.requestId || data.bookingId || data.chatId || "";
    const requestId = `${legacyChatId}`.trim();
    const mapped = {
      ...data,
      chatId: requestId,
      requestId,
      message: data.message,
      messageType: data.messageType || "text",
    };
    return await communicationEngine._sendCircumMessageHandler(mapped, context);
  } catch (error) {
    if (error instanceof functions.https.HttpsError) {
      throw error;
    }
    console.error(
        "Unexpected error in legacy sendMessage compatibility wrapper:",
        error,
    );
    throw new functions.https.HttpsError(
        "internal",
        "Message could not be sent.",
    );
  }
});

module.exports = sendMessage;
