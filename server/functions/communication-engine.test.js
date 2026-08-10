const assert = require("node:assert/strict");
const fs = require("node:fs");
const test = require("node:test");
const communicationEngine = require("./communication-engine");

const source = fs.readFileSync("communication-engine.js", "utf8");
const indexSource = fs.readFileSync("index.js", "utf8");

test("announcement recipients use JavaScript arrays correctly", () => {
  assert.equal(source.includes("recipients.add("), false);
  assert.equal(source.includes("recipients.push("), true);
});

test("notifications record delivery status, failures, and retries", () => {
  assert.match(source, /async function emitNotification/);
  assert.match(source, /function redactContactFields/);
  assert.match(source, /const safeData = redactContactFields\(data\)/);
  assert.match(source, /data: \{\.\.\.safeData, destination\}/);
  assert.match(source, /contactFieldPattern/);
  assert.match(source, /notificationId:\s*ref\.id/);
  assert.match(source, /correlationId/);
  assert.match(source, /deliveryStatus:\s*"persisted"/);
  assert.match(source, /deliveryState:\s*"persisted"/);
  assert.match(source, /pushDeliveryStatus:\s*"pending"/);
  assert.match(source, /pushDeliveryStatus:\s*"sent"/);
  assert.match(source, /status: "failed"/);
  assert.match(source, /failureReason:\s*"push_token_missing"/);
  assert.match(source, /pushProvider:\s*"fcm"/);
  assert.match(source, /retryCount:\s*0/);
  assert.match(
      source,
      /deliveryAttempts:\s*FieldValue\.increment\(1\)/,
  );
  assert.match(source, /retryCount:\s*FieldValue\.increment\(1\)/);
  assert.match(source, /lastDeliveryAttemptAt/);
  assert.match(source, /retryable:\s*true/);
  assert.match(source, /function notificationIdFor/);
  assert.match(source, /createHash\("sha256"\)/);
  assert.match(source, /if \(existing\.exists\)/);
  assert.match(source, /if \(!shouldSend\) return ref\.id/);
  assert.match(source, /privateNotificationFieldPattern/);
  assert.match(source, /notificationCorrelationFor/);
  assert.doesNotMatch(source, /db\.collection\("notifications"\)\.doc\(\)/);
});

test("notification privacy removes tokens, payment data, medical details, and contact fields", () => {
  const safe = communicationEngine.redactContactFields({
    deliveryId: "delivery-1",
    fcmToken: "private-token",
    stripePaymentIntentId: "pi_private",
    billingEmail: "billing@example.com",
    prescriptionName: "private medication",
    recipientPhone: "+44 7700 900000",
    nested: {status: "ready", secureStoryUrl: "https://example.test/?token=private"},
  });
  assert.deepEqual(safe, {deliveryId: "delivery-1", nested: {status: "ready"}});
  const text = communicationEngine.maskContactDetails(
      "Email billing@example.com about pi_secret and token=private-value",
  );
  assert.doesNotMatch(text, /billing@example\.com|pi_secret|private-value/);
});

test("notification and message identities are deterministic", () => {
  const correlation = communicationEngine.notificationCorrelationFor("delivery_update", {
    deliveryId: "delivery-1",
    status: "collected",
  });
  assert.equal(correlation, "delivery_update:delivery-1:collected");
  assert.equal(
      communicationEngine.messageDocumentId("chat-1", "sender-1", "message-123"),
      communicationEngine.messageDocumentId("chat-1", "sender-1", "message-123"),
  );
  assert.throws(
      () => communicationEngine.notificationCorrelationFor("system", {}),
      (error) => error.code === "failed-precondition",
  );
});

test("messages include backend-only diagnostic metadata", () => {
  assert.match(source, /messageId:\s*messageRef\.id/);
  assert.match(source, /conversationId:\s*chatId/);
  assert.match(source, /recipientIds/);
  assert.match(source, /correlationId/);
  assert.match(source, /participantDisplayName/);
  assert.match(source, /senderName/);
  assert.match(source, /senderDisplayName/);
  assert.match(source, /deliveryState:\s*"persisted"/);
  assert.match(source, /retryCount:\s*0/);
  assert.match(source, /notificationId:\s*null/);
  assert.match(source, /clientMessageId/);
  assert.match(source, /messageDocumentId/);
  assert.match(source, /duplicate/);
});

test("legacy sendMessage delegates to canonical communication handler", () => {
  const legacySource = fs.readFileSync("send-message.js", "utf8");
  assert.match(
      legacySource,
      /communicationEngine\._sendCircumMessageHandler\(mapped, context\)/,
  );
  assert.match(legacySource, /error instanceof functions\.https\.HttpsError/);
  assert.doesNotMatch(
      legacySource,
      /throw new functions\.https\.HttpsError\("internal", error\.message\)/,
  );
});

test("every Flutter communication mutation supplies an idempotency identity", () => {
  const clientFiles = [
    "../../lib/app/admin/admin_phase1_shell.dart",
    "../../lib/app/send_package/bloc/send_package_bloc.dart",
    "../../lib/app/send_package/view/ride_chats.dart",
    "../../lib/website/shared/circum_website_app.dart",
  ];
  for (const file of clientFiles) {
    const clientSource = fs.readFileSync(file, "utf8");
    const messageCalls = clientSource.match(/['"]sendCircumMessage['"]/g) || [];
    const messageIds = clientSource.match(/['"]clientMessageId['"]/g) || [];
    assert.equal(messageIds.length, messageCalls.length, `${file} must identify every message mutation`);
  }
  const adminSource = fs.readFileSync(clientFiles[0], "utf8");
  assert.match(adminSource, /httpsCallable\('sendCircumAnnouncement'\)[\s\S]{0,300}'announcementId'/);
});

test("notification retry is backend-authoritative and audited", () => {
  assert.match(source, /async function retryNotificationDelivery/);
  assert.match(source, /async function claimNotificationRetry/);
  assert.match(source, /isAdmin\(context\)/);
  assert.match(source, /getMessaging\(\)\.send/);
  assert.match(source, /pushDeliveryStatus:\s*"retrying"/);
  assert.match(source, /Notification is not eligible for retry/);
  assert.match(source, /actionType:\s*"notification_retry_sent"/);
  assert.match(source, /actionType:\s*"notification_retry_failed"/);
  assert.match(
      source,
      /exports\.retryNotificationDelivery = protectedCallable\.onCall/,
  );
  assert.match(
      indexSource,
      /exports\.retryNotificationDelivery = communicationEngine\./,
  );
});

test("automated notification retries are bounded and become exhausted", () => {
  const transient = communicationEngine.retryState(1, "messaging/internal-error", 0);
  assert.equal(transient.status, "failed");
  assert.equal(transient.retryable, true);
  assert.equal(transient.nextRetryAt.getTime(), 5 * 60 * 1000);
  assert.deepEqual(
      communicationEngine.retryState(5, "messaging/internal-error", 0),
      {status: "exhausted", retryable: false, nextRetryAt: null, permanent: false},
  );
  assert.equal(
      communicationEngine.retryState(
          1,
          "messaging/registration-token-not-registered",
          0,
      ).permanent,
      true,
  );
  assert.match(source, /schedule\("every 5 minutes"\)/);
  assert.match(source, /\.limit\(100\)/);
  assert.match(source, /sendEachForMulticast/);
  assert.match(source, /collection\("notificationTokens"\)/);
});

test("platform announcements persist notification ids and audit", () => {
  assert.match(source, /notificationIds = await Promise\.all/);
  assert.match(source, /actionType:\s*"platform_announcement_sent"/);
  assert.match(source, /recipientCount:\s*recipients\.length/);
  assert.match(
      source,
      /return \{ok: true, recipientCount: recipients\.length,/,
  );
});

test("closed support submissions create admin-visible read-only messages",
    () => {
      assert.match(
          source,
          /const initialMessage = maskContactDetails\(data\.initialMessage\)/,
      );
      assert.match(
          source,
          /const closeImmediately = data\.closeImmediately === true/,
      );
      assert.match(source, /if \(!closeImmediately\) \{/);
      assert.match(
          source,
          /const status = closeImmediately \? "closed" : "open"/,
      );
      assert.match(source, /readOnly: closeImmediately/);
      assert.match(source, /submittedBy/);
      assert.match(
          source,
          /closedReason: closeImmediately \? "one_way_submission" : null/,
      );
      assert.match(
          source,
          /chatRef\.collection\("messages"\)\.doc\("ticket_initial"\)/,
      );
      assert.match(source, /initialSupportRequest: true/);
      assert.match(
          source,
          /const initialText = maskContactDetails\(data\.message\)/,
      );
      assert.match(source, /closedSubmission: closeImmediately/);
      assert.match(source, /adminUnreadCount: initialMessage \? 1 : 0/);
    });

test("delivery system messages use deterministic event documents", () => {
  assert.match(source, /exports\.appendSystemMessage = async \(deliveryId, message, eventId\)/);
  assert.match(source, /type: "chat_system_message"/);
  assert.match(source, /const existing = await transaction\.get\(messageRef\)/);
  assert.match(source, /if \(existing\.exists\) return/);
  assert.match(source, /const safeMessage = maskContactDetails\(message\)/);
  assert.doesNotMatch(source, /collection\("messages"\)\.add\(\{[\s\S]*senderId: "circum-system"/);
});
