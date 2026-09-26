"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");

test("payment scheduler service exposes only bounded maintenance routes", () => {
  const source = fs.readFileSync("cloud-run-payment-schedulers.js", "utf8");
  const payoutSource = fs.readFileSync("rider-connect.js", "utf8");
  assert.match(source, /reconcileBusinessInvoiceCheckoutsCore/);
  assert.match(source, /scheduledRiderStripeStatusSyncCore/);
  assert.match(source, /recoverRiderPayoutsCore/);
  assert.match(source, /reconcilePendingDeliverySettlementsCore/);
  assert.match(source, /processHealthPlusRemindersCore/);
  assert.match(payoutSource, /FieldPath\.documentId\(\)/);
  assert.doesNotMatch(source, /createRiderTransferOrPayout\(stripeClient/);
  assert.doesNotMatch(source, /createBusinessInvoiceCheckout/);
});

test("payment scheduler container binds to Cloud Run PORT", () => {
  const source = fs.readFileSync("cloud-run-payment-schedulers.js", "utf8");
  assert.match(source, /process\.env\.PORT \|\| 8080/);
  assert.match(source, /"0\.0\.0\.0"/);
});

test("Pub/Sub Eventarc envelopes select only an explicit scheduler handler", () => {
  const {eventHandlerName} = require("./cloud-run-payment-schedulers");
  const wrap = (payload) => ({message: {data: Buffer.from(JSON.stringify(payload)).toString("base64")}});
  assert.equal(eventHandlerName(wrap({handler: "health"})), "health");
  assert.equal(eventHandlerName({data: wrap({handler: "scheduledRiderStripeStatusSync"})}), "scheduledRiderStripeStatusSync");
  assert.equal(eventHandlerName(wrap({handler: "scheduledRiderPayoutRecovery"})), "scheduledRiderPayoutRecovery");
  assert.equal(eventHandlerName(wrap({handler: 42})), "");
  assert.equal(eventHandlerName({message: {data: "%%%"}}), "");
  assert.equal(eventHandlerName(wrap({handler: "unknown"}), "/?__GCP_CloudEventsMode=CUSTOM_PUBSUB_projects%2Fcircum-2797c%2Ftopics%2Ffirebase-schedule-reconcilePendingDeliverySettlements-us-central1"), "reconcilePendingDeliverySettlements");
  assert.equal(eventHandlerName(wrap({handler: "unknown"}), "https://service.example/?topic=firebase-schedule-processHealthPlusReminders-us-central1"), "processHealthPlusReminders");
  assert.equal(eventHandlerName({}, "/", {"ce-source": "//pubsub.googleapis.com/projects/circum-2797c/topics/firebase-schedule-processHealthPlusReminders-us-central1"}), "processHealthPlusReminders");
});

test("Firebase Scheduler Eventarc metadata selects only the exact migrated topics", () => {
  const {eventHandlerName} = require("./cloud-run-payment-schedulers");
  assert.equal(eventHandlerName({}, "/?__GCP_CloudEventsMode=CUSTOM_PUBSUB_projects%2Fcircum-2797c%2Ftopics%2Ffirebase-schedule-reconcilePendingDeliverySettlements-us-central1"), "reconcilePendingDeliverySettlements");
  assert.equal(eventHandlerName({}, "/?__GCP_CloudEventsMode=CUSTOM_PUBSUB_projects%2Fcircum-2797c%2Ftopics%2Ffirebase-schedule-processHealthPlusReminders-us-central1"), "processHealthPlusReminders");
  assert.equal(eventHandlerName({}, "/?__GCP_CloudEventsMode=CUSTOM_PUBSUB_projects%2Fcircum-2797c%2Ftopics%2Funmigrated-topic"), "");
});
