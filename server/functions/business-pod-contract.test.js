"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const evidenceSource = fs.readFileSync(path.join(__dirname, "delivery-evidence.js"), "utf8");
const indexSource = fs.readFileSync(path.join(__dirname, "index.js"), "utf8");

test("Business POD is an App Check protected callable with Business role authority", () => {
  assert.match(evidenceSource, /exports\.getBusinessDeliveryEvidenceAccess\s*=\s*functions\.runWith\(\{enforceAppCheck: true\}\)/);
  assert.match(evidenceSource, /resolveBusinessAuthority/);
  assert.match(evidenceSource, /deliveries\.evidence/);
  assert.match(evidenceSource, /businessId \|\| delivery\.businessAccountId/);
  assert.match(evidenceSource, /deliveryEvidence/);
  assert.match(evidenceSource, /purpose.*HANDOVER/);
  assert.match(evidenceSource, /getSignedUrl/);
  assert.match(indexSource, /exports\.getBusinessDeliveryEvidenceAccess\s*=\s*deliveryEvidence\.getBusinessDeliveryEvidenceAccess/);
});

test("Business POD access excludes non-completed deliveries and missing proof", () => {
  assert.match(evidenceSource, /\["delivered", "completed"\]\.includes\(status\)/);
  assert.match(evidenceSource, /Proof of delivery is unavailable/);
  assert.match(evidenceSource, /evidence\.isVerifiedPhotoRecord/);
});
