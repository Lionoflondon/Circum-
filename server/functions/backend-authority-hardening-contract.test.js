"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

function source(name) {
  return fs.readFileSync(path.join(__dirname, "..", "..", name), "utf8");
}

test("Rider self-write rules exclude canonical identity and operational fields", () => {
  const rules = source("firestore.rules");
  const start = rules.indexOf("function riderSelfWritableFields()");
  const end = rules.indexOf("function isSafeRiderSelfCreate", start);
  assert.ok(start >= 0 && end > start);
  const writable = rules.slice(start, end);
  for (const field of ["username", "handle", "status", "availabilityStatus", "activeDelivery"]) {
    assert.doesNotMatch(writable, new RegExp(`'${field}'`), `${field} must be backend-owned`);
  }
});

test("material Rider lifecycle, evidence, adjustment, presence, Roth and referral callables enforce App Check", () => {
  const expectations = [
    ["server/functions/delivery-tracking.js", ["updateDeliveryTrackingStatus", "completeDelivery", "updateDeliveryLiveLocation"]],
    ["server/functions/delivery-evidence.js", ["recordDeliveryEvidence"]],
    ["server/functions/delivery-adjustments.js", ["reportLoadDiscrepancy", "reviewDeliveryAdjustment", "cancelAdjustedCollection", "createDeliveryAdjustmentPayment", "finalizeDeliveryAdjustmentPayment"]],
    ["server/functions/rider-presence.js", ["goOnline", "goOffline", "updateRiderPresence"]],
    ["server/functions/rider-account.js", ["updateRiderProfile", "submitRiderApplication", "updateRiderApplicationSection", "submitRiderDocument", "ensureRiderRothWallet"]],
    ["server/functions/referrals.js", ["ensureReferralCode", "attachReferralCode", "activateReferral"]],
  ];
  for (const [file, names] of expectations) {
    const text = source(file);
    for (const name of names) {
      const pattern = new RegExp(`exports\\.${name}\\s*=\\s*functions\\.runWith\\(\\{enforceAppCheck: true\\}\\)\\.https\\.onCall`);
      assert.match(text, pattern, `${file}:${name} must enforce App Check`);
    }
  }
});

test("Website evidence uses the canonical server-owned upload path", () => {
  const evidence = source("server/functions/delivery-evidence.js");
  assert.match(evidence, /bytesBase64/);
  assert.match(evidence, /evidence\.photoStoragePath\(deliveryId, photoId\)/);
  assert.match(evidence, /file\.save\(Buffer\.from\(inlineBytes, "base64"\)/);
  assert.match(evidence, /assignedTo\(delivery, context\.auth\.uid\)/);
});

test("Website client invokes the evidence authority instead of direct Storage upload", () => {
  const website = source("lib/website/shared/circum_website_app.dart");
  assert.match(website, /httpsCallable\('recordDeliveryEvidence'\)/);
  assert.doesNotMatch(website, /delivery_weight_evidence\//);
});

test("Roth mutation callables enforce App Check", () => {
  const text = source("server/functions/roth-ledger.js");
  for (const name of ["initialiseSenderWallet", "completeSenderWalletOnboarding", "requestSenderWalletDebit", "requestSenderWalletRefund", "applyCheckoutRoth", "issueRothCredit", "debitRothCredit"]) {
    assert.match(text, new RegExp(`exports\\.${name}\\s*=\\s*functions\\.runWith\\(\\{enforceAppCheck: true\\}\\)\\.https\\.onCall`));
  }
});
