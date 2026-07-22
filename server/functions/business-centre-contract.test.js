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
    "website",
    "shared",
    "circum_website_app.dart",
), "utf8");
const senderBusinessSource = fs.readFileSync(path.join(
    __dirname,
    "..",
    "..",
    "lib",
    "app",
    "business",
    "business_repository.dart",
), "utf8");

test("Business backend exports the canonical workspace, team, and payment callables", () => {
  for (const name of [
    "createBusinessAccount",
    "lookupBusinessByCompanyCode",
    "requestBusinessAccess",
    "reviewBusinessAccessRequest",
    "updateBusinessProfile",
    "inviteBusinessMember",
    "updateBusinessMemberRole",
    "updateBusinessMemberStatus",
    "removeBusinessMember",
    "recordBusinessIrisMoment",
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
  assert.match(businessAccessSource, /business_member_invited/);
  assert.match(businessAccessSource, /business_member_role_updated/);
  assert.match(businessAccessSource, /business_member_status_updated/);
  assert.match(businessAccessSource, /business_member_removed/);
  assert.match(businessAccessSource, /business_iris_moment_recorded/);
});

test("Sender Business client routes authoritative mutations through callables", () => {
  for (const callable of [
    "updateBusinessProfile",
    "inviteBusinessMember",
    "updateBusinessMemberRole",
    "updateBusinessMemberStatus",
    "removeBusinessMember",
    "recordBusinessIrisMoment",
  ]) {
    assert.match(senderBusinessSource, new RegExp(`httpsCallable\\('${callable}'\\)`));
  }
  assert.doesNotMatch(senderBusinessSource, /collection\('businessAccounts'\)\.doc\(account\.id\)\.set/);
  assert.doesNotMatch(senderBusinessSource, /FieldValue\.arrayUnion/);
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

test("Business invoice payment supports partial Roth plus remaining card payment", () => {
  assert.match(businessPaymentsSource, /calculateWalletCheckout\(\{[\s\S]*?orderTotalGbp: paymentAmount,[\s\S]*?walletBalanceGbp: walletBalance,[\s\S]*?selectedCurrency: "gbp"/);
  assert.match(businessPaymentsSource, /const rothAmount = split\.walletContributionGbp;/);
  assert.match(businessPaymentsSource, /const cardAmount = split\.remainingGbp;/);
  assert.match(businessPaymentsSource, /unit_amount: Math\.round\(cardAmount \* 100\)/);
  assert.match(businessPaymentsSource, /cardAmountGbp: `\$\{cardAmount\}`/);
  assert.match(businessPaymentsSource, /rothAmountGbp: `\$\{rothAmount\}`/);
  assert.match(businessPaymentsSource, /method: rothAmount > 0 \? `roth_\$\{requestedMethod\}` : requestedMethod/);
});

test("Business invoice Stripe payment without Roth charges the full balance by card", () => {
  assert.match(businessPaymentsSource, /const useRoth = data\.useRoth === true;/);
  assert.match(businessPaymentsSource, /const walletBalance = useRoth && `\$\{wallet\.status \|\| "active"\}` === "active" \? money\(wallet\.balance \|\| wallet\.availableBalance\) : 0;/);
  assert.match(businessPaymentsSource, /const cardAmount = split\.remainingGbp;/);
  assert.match(businessPaymentsSource, /unit_amount: Math\.round\(cardAmount \* 100\)/);
  assert.match(businessPaymentsSource, /rothAmountGbp: `\$\{rothAmount\}`/);
  assert.match(businessPaymentsSource, /method: rothAmount > 0 \? `roth_\$\{requestedMethod\}` : requestedMethod/);
  assert.match(businessPaymentsSource, /const requestedMethod = \["apple_pay", "google_pay", "saved_card", "card"\]\.includes\(`\$\{data\.paymentMethod \|\| ""\}`\) \? `\$\{data\.paymentMethod\}` : "card";/);
});

test("Business invoices expose printable PDF records without client-side invoice generation", () => {
  assert.match(senderWebSource, /Uri _businessInvoicePdfUri\(Map<String, dynamic> invoice\)/);
  assert.match(senderWebSource, /Business invoices are created by Circum Operations\./);
  assert.match(senderWebSource, /This copy is provided for business records and may be printed or saved as PDF\./);
  assert.match(senderWebSource, /onDownloadInvoice/);
  assert.match(senderWebSource, /Print \/ PDF/);
  assert.match(senderWebSource, /data:application\/pdf;base64/);
  assert.doesNotMatch(senderWebSource, /httpsCallable\('createBusinessInvoice'\)/);
  assert.doesNotMatch(senderWebSource, /\.collection\('businessInvoices'\)\.add/);
  assert.doesNotMatch(senderWebSource, /\.collection\('businessInvoices'\)\.doc\([^)]*\)\.set/);
});
