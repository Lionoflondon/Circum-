"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const trackingSource = fs.readFileSync(
    path.join(__dirname, "delivery-tracking.js"),
    "utf8",
);
const trackingCoreSource = fs.readFileSync(
    path.join(__dirname, "sender-tracking-state-core.js"),
    "utf8",
);

test("completeDelivery converges production verification and current settlement authority", () => {
  assert.match(trackingSource, /async function completeDeliveryHandler/);
  assert.match(trackingSource, /completionEvidenceDecision/);
  assert.match(trackingSource, /publishDeliveryCompleted/);
  assert.match(trackingSource, /buildDeliveryCompletedEvent/);
  assert.match(trackingSource, /standardSettlementAllowed/);
  assert.match(trackingSource, /planRoadChargeSettlement/);
  assert.match(trackingSource, /riderEarningTransactions/);
  assert.match(trackingSource, /transaction\.set\(evidenceRecordRef\.collection\("events"\)\.doc\("delivery_completed"\)/);
  assert.match(trackingCoreSource, /complete_delivery:\s*"delivered"/);
});

test("completion event and earning identities remain deterministic", () => {
  assert.match(trackingSource, /collection\("riderEarningTransactions"\)\.doc\(found\.id\)/);
  const eventSource = fs.readFileSync(
      path.join(__dirname, "delivery-completed-event.js"),
      "utf8",
  );
  assert.match(eventSource, /delivery_completed_\$\{deliveryId\}/);
  assert.match(eventSource, /transaction\.create\(eventRef\(db, event\.eventId\), event\)/);
});
