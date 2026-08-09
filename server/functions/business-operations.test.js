"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const {businessAuthority} = require("./business-authority");
const {sanitizeDelivery, sanitizeInvoice} = require("./business-operations")._private;

function doc(id, data) {
  return {id, data: () => data};
}

test("Business roles expose explicit operations, reporting, and finance authority", () => {
  const account = {teamMembers: [
    {userId: "ops", role: "operations", status: "active"},
    {userId: "finance", role: "finance", status: "active"},
    {userId: "viewer", role: "viewer", status: "active"},
  ]};
  assert.deepEqual(businessAuthority(account, {uid: "ops"}), {
    member: true, role: "operations", deliveryAuthorized: true,
    reportingAuthorized: true, financialAuthorized: false,
    ownerOrAdmin: false, legacyOnly: false, permissions: [],
  });
  assert.equal(businessAuthority(account, {uid: "finance"}).financialAuthorized, true);
  assert.equal(businessAuthority(account, {uid: "finance"}).deliveryAuthorized, false);
  assert.equal(businessAuthority(account, {uid: "viewer"}).reportingAuthorized, true);
  assert.equal(businessAuthority(account, {uid: "viewer"}).deliveryAuthorized, false);
});

test("Custom Business permissions cannot escape the approved catalogue", () => {
  const account = {teamMembers: [{userId: "custom", role: "custom", status: "active"}]};
  const authority = businessAuthority(account, {uid: "custom", customPermissions: [
    "deliveries.view", "finance.invoices.view", "platform.admin", "other_business.read",
  ]});
  assert.deepEqual(authority.permissions, ["deliveries.view", "finance.invoices.view"]);
  assert.equal(authority.deliveryAuthorized, true);
  assert.equal(authority.financialAuthorized, true);
  assert.equal(authority.ownerOrAdmin, false);
});

test("Business delivery projection is redacted and uses watchdog SLA truth", () => {
  const result = sanitizeDelivery(doc("delivery-1", {
    businessId: "business-1",
    pickupAddressCanonical: {formattedAddress: "The Shard, London SE1 9SG"},
    dropoffAddressCanonical: {formattedAddress: "Battersea Power Station, London SW11 8AL"},
    status: "collected",
    paidAmount: 21.35,
    serviceLevel: "standard",
    stripePaymentIntentId: "pi_private",
    senderEmail: "private@example.com",
  }), {active: true, openIncidentId: "delivery-1_collected_no_movement", incidentType: "collected_no_movement"});
  assert.equal(result.slaStatus, "RED");
  assert.equal(result.incidentType, "collected_no_movement");
  assert.equal(result.pickup, "The Shard, London SE1 9SG");
  assert.equal(result.amount, 21.35);
  assert.equal("stripePaymentIntentId" in result, false);
  assert.equal("senderEmail" in result, false);
});

test("Business invoice projection omits provider payment identifiers", () => {
  const result = sanitizeInvoice(doc("invoice-1", {
    invoiceNumber: "CIRCUM-1001",
    total: 100,
    balanceDue: 40,
    stripePaymentIntentId: "pi_private",
    stripeCustomerId: "cus_private",
  }));
  assert.equal(result.total, 100);
  assert.equal(result.balanceDue, 40);
  assert.equal("stripePaymentIntentId" in result, false);
  assert.equal("stripeCustomerId" in result, false);
});

test("Business workspace client no longer reads operational or finance collections directly", () => {
  const source = fs.readFileSync("../../lib/app/business/business_repository.dart", "utf8");
  assert.match(source, /httpsCallable\('getBusinessOperationsWorkspace'\)/);
  for (const collection of ["deliveryRequests", "businessInvoices", "prescriptionPickups", "giftRequests", "business_wallets"]) {
    assert.doesNotMatch(source, new RegExp(`collection\\('${collection}'\\)`));
  }
});

test("Business timeline is server-authorized, bounded, and client read-only", () => {
  const source = fs.readFileSync("business-operations.js", "utf8");
  const rules = fs.readFileSync("../../firestore.rules", "utf8");
  assert.match(source, /getBusinessDeliveryTimeline/);
  assert.match(source, /collection\("timeline"\)\.orderBy\("timestamp", "desc"\)\.limit\(100\)/);
  assert.match(rules, /match \/timeline\/\{eventId\}[\s\S]*?allow read: if isAdmin\(\);/);
});
