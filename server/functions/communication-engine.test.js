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
  assert.match(source, /deliveryStatus:\s*"persisted"/);
  assert.match(source, /pushDeliveryStatus:\s*"pending"/);
  assert.match(source, /pushDeliveryStatus:\s*"sent"/);
  assert.match(source, /pushDeliveryStatus:\s*"failed"/);
  assert.match(source, /failureReason:\s*"push_token_missing"/);
  assert.match(
      source,
      /deliveryAttempts:\s*FieldValue\.increment\(1\)/,
  );
  assert.match(source, /retryable:\s*true/);
});

test("notification retry is backend-authoritative and audited", () => {
  assert.match(source, /async function retryNotificationDelivery/);
  assert.match(source, /isAdmin\(context\)/);
  assert.match(source, /getMessaging\(\)\.send/);
  assert.match(source, /actionType:\s*"notification_retry_sent"/);
  assert.match(source, /actionType:\s*"notification_retry_failed"/);
  assert.match(
      source,
      /exports\.retryNotificationDelivery = functions\.https\.onCall/,
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
