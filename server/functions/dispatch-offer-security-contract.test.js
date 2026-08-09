/* eslint-disable max-len */
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const source = (name) => fs.readFileSync(path.join(__dirname, name), "utf8");

test("publication visibility and acceptance share one Rider dispatch authority", () => {
  for (const file of [
    "send-package.js",
    "get-avaliable-requests.js",
    "accept-ride-requests.js",
    "platform-notifications.js",
  ]) {
    assert.match(source(file), /dispatchEligibilityDecision/, file);
  }
});

test("dispatch callable response does not return delivery or Rider profile documents", () => {
  const value = source("send-package.js");
  assert.match(value, /functions\.runWith\(\{enforceAppCheck: true\}\)\.https\.onCall/);
  assert.match(value, /emitNotification = communicationEngine\.emitNotification/);
  assert.match(value, /correlationId: `delivery_offer:\$\{deliveryRequest\[0\]\.id\}:\$\{rider\.id\}`/);
  assert.doesNotMatch(value, /getMessaging/);
  assert.doesNotMatch(value, /fcmToken|pushToken/);
  assert.doesNotMatch(value, /return \{\s*error: e/);
  assert.match(value, /Delivery dispatch could not be completed/);
  const returnStart = value.lastIndexOf("return {");
  const returned = value.slice(returnStart);
  assert.doesNotMatch(returned, /request: deliveryRequest/);
  assert.doesNotMatch(returned, /closestRiders\s*[,}]/);
  assert.doesNotMatch(returned, /pushResults/);
  assert.doesNotMatch(returned, /fcmToken/);
});

test("available offers are projected through an explicit redaction boundary", () => {
  const value = source("get-avaliable-requests.js");
  assert.match(value, /riderOfferProjection\(doc\.id, requestData, decision\.distanceKm\)/);
  assert.doesNotMatch(value, /\.\.\.requestData/);
});

test("sendRiderUpdate never uses a caller token as FCM authority", () => {
  const value = source("send-rider-update.js");
  assert.match(value, /legacyToken && legacyToken !== authoritativeToken/);
  assert.doesNotMatch(value, /token:\s*data\.token/);
  assert.doesNotMatch(value, /token:\s*legacyToken/);
  assert.match(value, /recipientId = owner/);
  assert.match(value, /recipientId = assigned/);
  assert.match(value, /const status = text\(delivery\.data\.status \|\| delivery\.data\.deliveryStatus\)/);
  assert.doesNotMatch(value, /messageData\.status \|\| delivery\.data\.status/);
});
