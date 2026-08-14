/* eslint-disable max-len */
"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

function source(file) {
  return fs.readFileSync(path.join(__dirname, file), "utf8");
}

function exportUsesAppCheck(contents, exportName) {
  const pattern = new RegExp(`exports\\.${exportName}\\s*=\\s*functions\\.runWith\\(\\{enforceAppCheck:\\s*true\\}\\)\\.https\\.onCall`);
  assert.match(contents, pattern, `${exportName} must enforce App Check`);
}

test("core delivery lifecycle callables enforce App Check", () => {
  const index = source("index.js");
  const accept = source("accept-ride-requests.js");
  assert.match(
      accept,
      /const acceptRideRequests\s*=\s*functions\.runWith\(\{enforceAppCheck:\s*true\}\)\.https\.onCall/,
      "acceptRideRequests must enforce App Check",
  );
  assert.match(index, /exports\.acceptRideRequests\s*=\s*acceptRideRequests/);

  const tracking = source("delivery-tracking.js");
  for (const exportName of [
    "recordDeliveryEvidence",
    "getDeliveryEvidenceAccess",
    "updateDeliveryTrackingStatus",
    "updateDeliveryLiveLocation",
  ]) {
    exportUsesAppCheck(tracking, exportName);
  }
  assert.match(index, /exports\.recordDeliveryEvidence\s*=\s*deliveryTracking\.recordDeliveryEvidence/);
  assert.match(index, /exports\.getDeliveryEvidenceAccess\s*=\s*deliveryTracking\.getDeliveryEvidenceAccess/);
  assert.match(index, /exports\.updateDeliveryTrackingStatus\s*=\s*deliveryTracking\.updateDeliveryTrackingStatus/);
  assert.match(index, /exports\.updateDeliveryLiveLocation\s*=\s*deliveryTracking\.updateDeliveryLiveLocation/);

  const policy = source("delivery-policy.js");
  for (const exportName of [
    "requestSenderCancellation",
    "previewSenderCancellation",
    "recordRiderArrival",
    "recordArrivalZoneCheck",
    "recordCustomerArrivalResponse",
    "reportWaitingContext",
    "markRiderNoShow",
  ]) {
    exportUsesAppCheck(policy, exportName);
  }
  assert.match(index, /exports\.requestSenderCancellation\s*=\s*deliveryPolicy\.requestSenderCancellation/);
  assert.match(index, /exports\.cancelDelivery\s*=\s*deliveryPolicy\.requestSenderCancellation/);
  assert.match(index, /exports\.recordRiderArrival\s*=\s*deliveryPolicy\.recordRiderArrival/);
});
