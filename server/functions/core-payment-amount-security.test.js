/* eslint-disable max-len, require-jsdoc */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const indexSource = fs.readFileSync(path.join(__dirname, "index.js"), "utf8");
const senderBookingSource = fs.readFileSync(path.join(__dirname, "sender-booking.js"), "utf8");
const accountBlocSource = fs.readFileSync(path.join(
    __dirname,
    "..",
    "..",
    "lib",
    "app",
    "account",
    "bloc",
    "account_bloc.dart",
), "utf8");
const sendBlocSource = fs.readFileSync(path.join(
    __dirname,
    "..",
    "..",
    "lib",
    "app",
    "send_package",
    "bloc",
    "send_package_bloc.dart",
), "utf8");
const accountStateSource = fs.readFileSync(path.join(
    __dirname,
    "..",
    "..",
    "lib",
    "app",
    "account",
    "bloc",
    "account_state.dart",
), "utf8");
const webSenderSource = fs.readFileSync(path.join(
    __dirname,
    "..",
    "..",
    "lib",
    "website",
    "shared",
    "circum_website_app.dart",
), "utf8");

test("legacy standard delivery payment HTTP endpoints are retired", () => {
  assert.doesNotMatch(indexSource, /exports\.StripePayEndpointMethodId/);
  assert.doesNotMatch(indexSource, /exports\.createPaymentIntent/);
  assert.doesNotMatch(indexSource, /exports\.StripePayEndpointIntentId/);
  assert.doesNotMatch(indexSource, /exports\.confirmPaymentIntent/);
  assert.doesNotMatch(indexSource, /createPaymentIntentHandler/);
  assert.doesNotMatch(indexSource, /legacyCorePaymentSessions/);
  assert.doesNotMatch(accountBlocSource, /createPaymentIntent/);
  assert.doesNotMatch(accountBlocSource, /confirmPaymentIntent/);
});

test("Sender mobile uses canonical quote, payment session, and paid delivery callables", () => {
  assert.match(accountBlocSource, /httpsCallable\('createSenderBookingQuote'\)/);
  assert.match(accountBlocSource, /httpsCallable\('createSenderPaymentSession'\)/);
  assert.match(sendBlocSource, /_callableMap\('createSenderPaidDelivery'/);
  assert.doesNotMatch(sendBlocSource, /collection\("deliveryRequests"\)\.doc\(user\?\.uid\)\.set/);
  assert.match(accountStateSource, /final String\? quoteId/);
  assert.match(accountStateSource, /final String\? paymentSessionId/);
  assert.match(accountBlocSource, /quoteId:\s*paymentIntentResult\['quoteId'\]/);
  assert.match(accountBlocSource, /paymentSessionId:\s*paymentIntentResult\['paymentSessionId'\]/);
});

test("canonical payment authority calculates and records authoritative pricing", () => {
  assert.match(senderBookingSource, /exports\.createSenderBookingQuote/);
  assert.match(senderBookingSource, /verifiedPhotoAnalysis\(\{/);
  assert.match(senderBookingSource, /quotePayload\(\{\s*\.\.\.\(data \|\| \{\}\),\s*\.\.\.\(businessContext \|\| \{\}\),\s*\}, sender\.uid, serverPhotoAnalysis\)/);
  assert.match(senderBookingSource, /clientDisplayQuote/);
  assert.match(senderBookingSource, /pricingDiscrepancyPence/);
  assert.match(senderBookingSource, /exports\.createSenderPaymentSession/);
  assert.match(senderBookingSource, /const quoteSnap = await db\.collection\("senderBookingQuotes"\)/);
  assert.match(senderBookingSource, /quoteSnap\.data\(\)\.userId !== sender\.uid/);
  assert.match(senderBookingSource, /calculateWalletCheckout/);
  assert.match(senderBookingSource, /collection\("senderPaymentSessions"\)\.doc\(quoteId\)/);
  assert.match(senderBookingSource, /existingSessionSnap\.exists/);
  assert.match(senderBookingSource, /requestedSessionKey/);
  assert.match(senderBookingSource, /stripe\.paymentIntents\.create/);
  assert.match(senderBookingSource, /const idempotencyKey = `sender_booking_\$\{quoteId\}`/);
});

test("Sender web Checkout forces a fresh Stripe session on retry", () => {
  assert.match(senderBookingSource, /payment_method_types: \["card"\]/);
  assert.match(senderBookingSource, /checkoutKey: requestedSessionKey/);
  assert.match(senderBookingSource, /checkoutAttempt/);
  assert.match(senderBookingSource, /web_checkout_retry_forces_fresh_session/);
  assert.match(senderBookingSource, /stripe\.checkout\.sessions\.create\(/);
  assert.doesNotMatch(senderBookingSource, /stripe\.checkout\.sessions\.retrieve\(existingSession\.checkoutSessionId\)/);
});

test("Sender clients do not hardcode Stripe runtime keys", () => {
  const envSource = fs.readFileSync(path.join(__dirname, "../../lib/env/env.dart"), "utf8");
  const senderBuildScript = fs.readFileSync(path.join(__dirname, "../../scripts/build_sender_app_web.sh"), "utf8");
  const deployWorkflow = fs.readFileSync(path.join(__dirname, "../../.github/workflows/deploy_sender_web.yml"), "utf8");
  const releaseWorkflow = fs.readFileSync(path.join(__dirname, "../../.github/workflows/rc1_release_build.yml"), "utf8");
  assert.doesNotMatch(envSource, /pk_(test|live)_/);
  assert.match(envSource, /String\.fromEnvironment\('STRIPE_PUBLISHABLE_KEY'\)/);
  assert.match(senderBuildScript, /Missing STRIPE_PUBLISHABLE_KEY/);
  assert.match(senderBuildScript, /--dart-define=STRIPE_PUBLISHABLE_KEY=/);
  assert.match(deployWorkflow, /secrets\.STRIPE_PUBLISHABLE_KEY/);
  assert.match(releaseWorkflow, /secrets\.STRIPE_PUBLISHABLE_KEY/);
});

test("Sender payment callable responses exclude Firestore sentinel fields", () => {
  const paymentSource = senderBookingSource.match(/exports\.createSenderPaymentSession[\s\S]*?\n\}\);/)[0];
  assert.match(paymentSource, /const sessionBase = \{/);
  assert.doesNotMatch(paymentSource, /return \{\s*\.\.\.sessionBase/);
  assert.doesNotMatch(paymentSource, /return \{\s*\.\.\.existingSession/);
  assert.match(paymentSource, /createdAt: FieldValue\.serverTimestamp\(\)/);
  assert.match(paymentSource, /updatedAt: FieldValue\.serverTimestamp\(\)/);
});

test("Sender Stripe checkout refreshes stale customer records", () => {
  assert.match(senderBookingSource, /const existingCustomerId = text\(user\.stripeCustomerId \|\| user\.customerId\)/);
  assert.match(senderBookingSource, /await stripe\.customers\.retrieve\(existingCustomerId\)/);
  assert.match(senderBookingSource, /existingCustomer && !existingCustomer\.deleted/);
  assert.match(senderBookingSource, /code !== "resource_missing"/);
  assert.match(senderBookingSource, /Refreshing missing Sender Stripe customer/);
  assert.match(senderBookingSource, /await stripe\.customers\.create\(\{/);
});

test("canonical paid delivery finalization requires succeeded payment and is idempotent", () => {
  assert.match(senderBookingSource, /exports\.createSenderPaidDelivery/);
  assert.match(senderBookingSource, /paymentSessionId/);
  assert.match(senderBookingSource, /Stripe payment must be confirmed before delivery creation/);
  assert.match(senderBookingSource, /senderDeliveryIdempotency/);
  assert.match(senderBookingSource, /paymentStatus: "paid"/);
  assert.match(senderBookingSource, /pricingBreakdown: quote/);
});

test("canonical backend delivery records include Rider display aliases", () => {
  assert.match(senderBookingSource, /const RIDER_DELIVERY_FARE_SHARE = 0\.65/);
  assert.match(senderBookingSource, /function riderDisplayAliases\(/);
  assert.match(senderBookingSource, /function riderPayoutFromQuote\(/);
  assert.match(senderBookingSource, /totalRiderEarnings/);
  assert.match(senderBookingSource, /const riderAliases = riderDisplayAliases\(\{quote, data, vanguardFields\}\)/);
  assert.match(senderBookingSource, /\.\.\.riderAliases/);
  assert.match(senderBookingSource, /riderEarning: riderPayout/);
  assert.match(senderBookingSource, /riderEligibleFare: riderEligibleFareFromQuote\(quote\)/);
  assert.match(senderBookingSource, /riderPayoutCalculationVersion: "65_35_v1"/);
  assert.match(senderBookingSource, /distanceText: distanceMiles > 0/);
  assert.match(senderBookingSource, /durationText: durationMinutes > 0/);
  assert.match(senderBookingSource, /requiresVanguard: vanguardFields\.vanguardProtocolEnabled === true/);
  assert.match(senderBookingSource, /pickupWindow: pickupWindow \|\| null/);
});

test("canonical delivery public records redact direct phone contact fields", () => {
  assert.match(senderBookingSource, /contactMethod: "circum_relay"/);
  assert.match(senderBookingSource, /maskedCommunicationOnly: true/);
  assert.match(senderBookingSource, /privateContactDetails: stripUndefined/);
  assert.match(senderBookingSource, /pickupPhone: pickup\.phone \|\| ""/);
  assert.match(senderBookingSource, /receiverPhone: data\.recipient && data\.recipient\.phone \|\| dropoff\.phone \|\| ""/);
  assert.match(senderBookingSource, /transaction\.set\(db\.collection\("deliveryRequestsPrivate"\)\.doc\(deliveryRef\.id\)/);
  assert.doesNotMatch(senderBookingSource, /phone: pickup\.phone \|\| ""/);
  assert.doesNotMatch(senderBookingSource, /phone: dropoff\.phone \|\| data\.recipient && data\.recipient\.phone \|\| ""/);
});

test("Sender Web checkout uses canonical payment callables and never writes paid deliveries directly", () => {
  const confirmPaymentMatch = webSenderSource.match(/Future<void> _confirmPayment\(\) async \{[\s\S]*?\n {2}Future<bool\?> _confirmAuthoritativeWebQuote/);
  assert.ok(confirmPaymentMatch, "web _confirmPayment implementation not found");
  const confirmPaymentSource = confirmPaymentMatch[0];
  assert.match(confirmPaymentSource, /httpsCallable\('createSenderBookingQuote'\)/);
  assert.match(confirmPaymentSource, /httpsCallable\('createSenderPaymentSession'\)/);
  assert.match(confirmPaymentSource, /'checkoutMode': 'web_checkout'/);
  assert.match(confirmPaymentSource, /'rothEnabled': _deliveryUseRoth/);
  assert.match(confirmPaymentSource, /launchUrl\(checkoutUrl, webOnlyWindowName: '_self'\)/);
  assert.match(confirmPaymentSource, /httpsCallable\('createSenderPaidDelivery'\)/);
  assert.match(webSenderSource, /httpsCallable\('finalizeSenderWebCheckout'\)/);
  assert.match(webSenderSource, /Secure Stripe Checkout/);
  assert.match(webSenderSource, /Card or Apple Pay/);
  assert.doesNotMatch(confirmPaymentSource, /Stripe\.instance\.presentPaymentSheet/);
  assert.doesNotMatch(confirmPaymentSource, /'rothEnabled': false/);
  assert.doesNotMatch(confirmPaymentSource, /collection\('webSenderRequests'\)/);
  assert.doesNotMatch(confirmPaymentSource, /collection\('deliveryRequests'\)\.doc\(id\)/);
  assert.doesNotMatch(confirmPaymentSource, /collection\('chats'\)/);
  assert.doesNotMatch(confirmPaymentSource, /batch\.commit\(\)/);
});

test("Sender web Checkout verifies Stripe and defers Roth debit until delivery creation", () => {
  assert.match(senderBookingSource, /verifiedStripePaidGbpSession\(sessionData, \{/);
  assert.match(senderBookingSource, /expectedAmountGBP: payment\.remainingAmount/);
  assert.match(senderBookingSource, /Number\(payment\.rothAppliedAmount \|\| 0\) > 0/);
  assert.match(senderBookingSource, /roth_debit_deferred_until_delivery_creation/);
  assert.match(senderBookingSource, /const walletDebitRef = db\.collection\("walletTransactions"\)\.doc\(`wallet_delivery_\$\{paymentSessionId\}`\)/);
  assert.match(senderBookingSource, /transaction\.set\(walletDebitRef, \{/);
  assert.match(senderBookingSource, /transaction\.set\(deliveryRef, stripUndefined\(\{/);
  assert.match(senderBookingSource, /rothDebitStatus: "completed"/);
  assert.doesNotMatch(senderBookingSource, /rothLedger\.applyWalletDebit/);
});

test("Sender Roth payments resolve and debit canonical plus legacy wallet records", () => {
  assert.match(senderBookingSource, /function walletRefsForSender\(db, sender\)/);
  assert.match(senderBookingSource, /senderWalletRef: db\.collection\("senderWallets"\)\.doc\(sender\.uid\)/);
  assert.match(senderBookingSource, /const \[legacySnap, projectionSnap\] = await Promise\.all\(\[/);
  assert.match(senderBookingSource, /projectionSnap\.exists \? projectionSnap\.data\(\) \|\| \{\} : \{\}/);
  assert.match(senderBookingSource, /Math\.max\(\.\.\.candidates\)/);
  assert.match(senderBookingSource, /Sender wallet projection drift detected during payment/);
  assert.match(senderBookingSource, /const projectionBalance = Number\(senderWallet\.balance == null \?/);
  assert.match(senderBookingSource, /walletBalanceBefore = money\(availableBalances\.length \? Math\.max\(\.\.\.availableBalances\) : 0\)/);
  assert.match(senderBookingSource, /transaction\.set\(senderWalletRef, \{/);
  assert.match(senderBookingSource, /balance: walletBalanceAfter/);
});

test("legacy endTrip cannot complete or settle deliveries", () => {
  assert.match(indexSource, /exports\.endTrip = functions\.https\.onRequest/);
  assert.match(indexSource, /res\.status\(410\)\.send/);
  assert.match(indexSource, /retired_delivery_completion_endpoint/);
  assert.match(indexSource, /Use updateDeliveryTrackingStatus/);
});
