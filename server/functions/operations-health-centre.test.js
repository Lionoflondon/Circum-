const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const health = require("./operations-health-centre");

test("Operations health scoring certifies only when critical services pass", () => {
  const items = [
    {service: "Dispatch Pipeline", status: "PASS"},
    {service: "Stripe", status: "PASS"},
    {service: "Firestore", status: "PASS"},
  ];
  assert.equal(health.weightedScore(items), 100);
  assert.equal(health.deploymentCertification(items), "CERTIFIED");
  assert.equal(health.statusForScore(100), "PASS");
  assert.equal(health.statusForScore(70), "WARNING");
  assert.equal(health.statusForScore(40), "FAIL");
});

test("Operations deployment gate blocks critical health failures", () => {
  const items = [
    {service: "Dispatch Pipeline", status: "FAIL"},
    {service: "IRIS", status: "PASS"},
  ];
  assert.equal(health.deploymentCertification(items), "NOT_CERTIFIED");
});

test("Operations health repair contract cannot mutate finance or approve users", () => {
  const source = fs.readFileSync(path.join(__dirname, "operations-health-centre.js"), "utf8");
  assert.match(source, /financialRecordsMutated:\s*0/);
  assert.match(source, /usersApproved:\s*0/);
  assert.match(source, /approve:\s*false/);
  assert.doesNotMatch(source, /collection\("wallets"\)\.doc\([^)]*\)\.set/);
  assert.doesNotMatch(source, /collection\("rothLedger"\)\.doc\([^)]*\)\.set/);
  assert.doesNotMatch(source, /collection\("payments"\)\.doc\([^)]*\)\.set/);
});

test("Operations Health Centre callables are Admin-only audited and exported", () => {
  const source = fs.readFileSync(path.join(__dirname, "operations-health-centre.js"), "utf8");
  const index = fs.readFileSync(path.join(__dirname, "index.js"), "utf8");
  assert.match(source, /requireAdmin\(context, "Operations Health Centre access is required\."\)/);
  assert.match(source, /requireAdmin\(context, "Operations Health Repair access is required\."\)/);
  assert.match(source, /requireAdmin\(context, "Live Delivery Diagnostics access is required\."\)/);
  assert.match(source, /adminAuditLogs/);
  assert.match(source, /immutable:\s*true/);
  assert.match(index, /exports\.operationsHealthScan =\s*\n\s*operationsHealthCentre\.operationsHealthScan\(\)/);
  assert.match(index, /exports\.operationsHealthRepair =\s*\n\s*operationsHealthCentre\.operationsHealthRepair\(\)/);
  assert.match(index, /exports\.liveDeliveryDiagnostics =\s*\n\s*operationsHealthCentre\.liveDeliveryDiagnostics\(\)/);
});

test("Live delivery diagnostics reports first blocked lifecycle stage", () => {
  const missingBooking = health.deliveryStageReport({});
  assert.equal(missingBooking.result, "BLOCKED");
  assert.equal(missingBooking.stoppedAt, "Booking");

  const paidSearching = health.deliveryStageReport({
    paymentStatus: "paid",
    matchingStatus: "available",
    stripePaymentIntentId: "pi_test",
  });
  assert.equal(paidSearching.result, "READY");
  assert.equal(paidSearching.stoppedAt, "Offer Broadcast");
});
