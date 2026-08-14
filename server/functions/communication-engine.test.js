const assert = require("node:assert/strict");
const fs = require("node:fs");
const test = require("node:test");

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
  assert.match(source, /pushDeliveryStatus:\s*"failed"/);
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
});

test("message retries can reuse a stable client id without duplicating writes", () => {
  assert.match(source, /clientMessageId/);
  assert.match(source, /client_\$\{clientMessageId\}/);
  assert.match(source, /const existing = await transaction\.get\(messageRef\)/);
  assert.match(source, /existingData\.senderId !== senderId/);
  assert.match(source, /existingData\.messageText !== message/);
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

test("notification retry is backend-authoritative and audited", () => {
  assert.match(source, /async function retryNotificationDelivery/);
  assert.match(source, /isAdmin\(context\)/);
  assert.match(source, /getMessaging\(\)\.send/);
  assert.match(source, /actionType:\s*"notification_retry_sent"/);
  assert.match(source, /actionType:\s*"notification_retry_failed"/);
  assert.match(
      source,
      /exports\.retryNotificationDelivery = functions\.runWith\(\{enforceAppCheck: true\}\)\.https\.onCall/,
  );
  assert.match(
      indexSource,
      /exports\.retryNotificationDelivery = communicationEngine\./,
  );
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
      assert.match(source, /closedSubmission: closeImmediately/);
      assert.match(source, /adminUnreadCount: initialMessage \? 1 : 0/);
    });
