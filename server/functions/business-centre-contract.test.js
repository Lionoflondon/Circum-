/* eslint-disable max-len */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const businessAccessSource = fs.readFileSync(path.join(__dirname, "business-access.js"), "utf8");
const businessPaymentsSource = fs.readFileSync(path.join(__dirname, "business-payments.js"), "utf8");
const indexSource = fs.readFileSync(path.join(__dirname, "index.js"), "utf8");
const senderWebSource = fs.readFileSync(path.join(
    __dirname,
    "..",
    "..",
    "lib",
    "web_sender_app.dart",
), "utf8");

test("Business backend exports the canonical workspace, team, and payment callables", () => {
  for (const name of [
    "createBusinessAccount",
    "lookupBusinessByCompanyCode",
    "requestBusinessAccess",
    "reviewBusinessAccessRequest",
    "updateBusinessProfile",
    "updateBusinessMemberRole",
    "removeBusinessMember",
  ]) {
    assert.match(businessAccessSource, new RegExp(`exports\\.${name}\\s*=`));
    assert.match(indexSource, new RegExp(`exports\\.${name}\\s*=\\s*businessAccess\\.${name}`));
  }
  for (const name of [
    "createBusinessInvoiceCheckout",
    "createBusinessRothCheckout",
  ]) {
    assert.match(businessPaymentsSource, new RegExp(`exports\\.${name}\\s*=`));
    assert.match(indexSource, new RegExp(`exports\\.${name}\\s*=\\s*businessPayments\\.${name}`));
  }
});

test("Business administration is role-gated and audited", () => {
  assert.match(businessAccessSource, /BUSINESS_ADMIN_ROLES = new Set\(\["owner", "admin", "manager"\]\)/);
  assert.match(businessAccessSource, /requireBusinessAdmin/);
  assert.match(businessAccessSource, /exports\.updateBusinessMemberRole[\s\S]*?requireAuth\(context\);[\s\S]*?const memberUserId/);
  assert.match(businessAccessSource, /exports\.removeBusinessMember[\s\S]*?requireAuth\(context\);[\s\S]*?const memberUserId/);
  assert.match(businessAccessSource, /business_profile_updated/);
  assert.match(businessAccessSource, /business_member_role_updated/);
  assert.match(businessAccessSource, /business_member_removed/);
});

test("Sender Web exposes the Business Centre without placeholder routes", () => {
  assert.match(senderWebSource, /_SenderStep\.business/);
  assert.match(senderWebSource, /class _BusinessCentreStep/);
  assert.match(senderWebSource, /Business Centre/);
  assert.match(senderWebSource, /httpsCallable\('createBusinessAccount'\)/);
  assert.match(senderWebSource, /httpsCallable\('lookupBusinessByCompanyCode'\)/);
  assert.match(senderWebSource, /httpsCallable\('requestBusinessAccess'\)/);
  assert.match(senderWebSource, /httpsCallable\('reviewBusinessAccessRequest'\)/);
  assert.match(senderWebSource, /httpsCallable\('updateBusinessProfile'\)/);
  assert.match(senderWebSource, /httpsCallable\('updateBusinessMemberRole'\)/);
  assert.match(senderWebSource, /httpsCallable\('removeBusinessMember'\)/);
  assert.match(senderWebSource, /httpsCallable\('createBusinessInvoiceCheckout'\)/);
  assert.match(senderWebSource, /httpsCallable\('createBusinessRothCheckout'\)/);
  assert.doesNotMatch(senderWebSource, /Business Centre[\s\S]{0,4000}Coming Soon/);
});
