/* eslint-disable max-len, require-jsdoc */
"use strict";
// Standalone disposable certification runtime. Never imported by index.js.
const fs = require("node:fs");
const http = require("node:http");
const crypto = require("node:crypto");
const {spawn} = require("node:child_process");
const {validate} = require("./isolated-payment-certification-guard");
validate(process.env);
const incarnation = crypto.randomUUID();
const events = [];
let connectHandler;
let signingSecret = "";
async function start() {
  const emulator = spawn("java", ["-jar", "/opt/firestore.jar", "--host=127.0.0.1", "--port=8081", "--project_id=demo-pay-cert-20261016"], {stdio: "ignore"});
  emulator.on("exit", () => process.exit(1));
  let ready = false;
  for (let n = 0; n < 120; n++) {
    try {
 const r = await fetch("http://127.0.0.1:8081/"); if (r.status < 500) {
 ready = true; break;
}
} catch (_) {/* emulator boot */}
    await new Promise((r) => setTimeout(r, 500));
  }
  if (!ready) throw new Error("Emulator startup failed");
  const {initializeApp} = require("firebase-admin/app");
  const {getFirestore} = require("firebase-admin/firestore");
  initializeApp({projectId: process.env.GCLOUD_PROJECT});
  const db = getFirestore();
  const stripe = new (require("stripe"))(process.env.STRIPE_SECRET_KEY, {maxNetworkRetries: 0, timeout: 20000});
  stripe._circumStripeMode = "test";
  if ((await stripe.accounts.retrieve()).id !== process.env.CIRCUM_CERT_ACCOUNT) throw new Error("Sandbox account mismatch");
  const quiet = {info() {}, log() {}, warn() {}, error() {}};
  const processor = require("./stripe-webhook-core").createStripeWebhookProcessor({
    stripe, db, resolveRuntimeConfig: () => ({mode: "test", webhookSecret: signingSecret}),
    assertEventMode: require("./stripe-config").assertStripeEventMode,
    messaging: {send: async () => {
 throw new Error("External messaging forbidden");
}},
    giftsPayment: require("./gifts-payment"), ratingsTipping: require("./ratings-tipping"),
    stripeRefunds: require("./stripe-refunds"), senderBooking: require("./sender-booking"),
    businessPayments: require("./business-payments"), deliveryAdjustmentPayments: require("./delivery-adjustment-checkout"),
    healthPlus: require("./health-plus"), healthMembershipLifecycle: require("./health-membership-lifecycle"),
    rothLedger: require("./roth-ledger"), routeCheckoutSessionCompleted: require("./checkout-session-router").routeCheckoutSessionCompleted, logger: quiet,
  });
  async function rpc(data) {
    if (data.action === "configure") {
      if (!/^whsec_[A-Za-z0-9]+$/.test(data.secret || "")) throw new Error("Signing secret required");
      signingSecret = data.secret; return {configured: true};
    }
    if (data.action === "configure_connect") {
      if (!/^whsec_[A-Za-z0-9]+$/.test(data.secret || "")) throw new Error("Signing secret required");
      process.env.STRIPE_CONNECT_WEBHOOK_SECRET = data.secret;
      connectHandler = require("./rider-connect").handleStripeConnectWebhook(stripe);
      return {configured: true};
    }
    if (data.action === "state") {
      const names = ["businessInvoices", "business_wallets", "deliveryRequests", "deliveryAdjustments", "healthPlusMemberships", "giftRecurringSeries", "giftRecurringRenewals", "giftRequests", "emailQueue", "paymentArtifactReconciliations", "senderPaymentSessions", "giftPaymentDrafts", "wallets", "senderWallets", "payoutRequests", "riderEarnings", "riderPayoutAudit", "stripeConnectEvents", "deliveryMaintenanceJobs"];
      const result = {};
      for (const name of names) result[name] = (await db.collection(name).get()).docs.map((d) => ({id: d.id, ...d.data()}));
      return {incarnation, events, records: result};
    }
    if (!/^cert_[a-f0-9]{12}$/.test(data.id || "")) throw new Error("Invalid synthetic fixture ID");
    const id = data.id;
    if (data.action === "connect_seed") {
      const account = await stripe.accounts.retrieve(data.accountId);
      if (account.metadata.purpose !== "CIRCUM-isolated-payment-certification-20261016" || ![60, 260].includes(data.amountPence)) throw new Error("Unowned Connect fixture");
      await db.doc(`payoutRequests/${id}`).create({riderId: id, stripeAccountId: account.id, amount: data.amountPence / 100, riderNetPayout: data.amountPence / 100, fundsReserved: true, status: "requested"});
      await db.doc(`riderEarnings/${id}`).create({availableBalance: 0, pendingWithdrawal: data.amountPence / 100, totalWithdrawn: 0, withdrawnEarnings: 0});
      return {seeded: true};
    }
    if (data.action === "connect_bind") {
      const t = await stripe.transfers.retrieve(data.transferId);
      const snap = await db.doc(`payoutRequests/${id}`).get();
      if (!snap.exists || t.metadata.payoutRequestId !== id || t.destination !== snap.data().stripeAccountId) throw new Error("Transfer lineage mismatch");
      await snap.ref.update({stripeTransferId: t.id});
      return {bound: true};
    }
    if (data.action === "adjustment_native") {
      await db.doc(`deliveryAdjustments/${id}`).create({senderId: id, bookingId: id, riderId: "cert_rider", status: "awaiting_sender_payment", adminDecision: "approve", additionalAmount: 1, revisedQuote: 9});
      await db.doc(`deliveryRequests/${id}`).create({status: "awaiting_sender_adjustment", preAdjustmentStatus: "accepted"});
      return require("./delivery-adjustment-checkout").createPayment({db, stripe, adjustmentId: id, senderId: id, hosted: false});
    }
    if (data.action === "sender_native") {
      const payload = {requestId: id, pickup: {address: "Synthetic QA pickup", coordinates: {lat: 51.5007, lng: -0.1246}}, dropoff: {address: "Synthetic QA dropoff", coordinates: {lat: 51.5033, lng: -0.1195}}, recipient: {name: "Synthetic QA recipient"}, parcel: {itemName: "Books", description: "Books", weightKg: 1}, iris: {recommendedVehicle: "Motorbike"}, deliveryTime: {type: "now"}};
      await db.doc(`senderBookingQuotes/${id}`).create({quoteId: id, userId: id, currency: "GBP", total: 4, amountDue: 4, finalAmount: 4, selectedSpeed: "standard", selectedVehicle: "motorbike", distanceMiles: 2, vanguardProtocolEnabled: true, vanguardFee: 1.99, parcelAuthority: {description: "Books", weightKg: 1}, route: {origin: {latitude: 51.5007, longitude: -0.1246}, destination: {latitude: 51.5033, longitude: -0.1195}}});
      return require("./sender-booking")._qa.createSenderPaymentSession(stripe, {quoteId: id, fallbackMethod: "card", checkoutMode: "payment_intent", deliveryPayload: payload}, {auth: {uid: id, token: {email: id + "@example.invalid", name: "Synthetic QA Sender"}}}, {db});
    }
    if (data.action === "gift_native") {
      const email = id + "@example.invalid";
      await db.doc(`wallets/${email}`).create({uid: id, userId: email, userEmail: email, normalizedEmail: email, balance: 49, rothCredit: 49, currency: "GBP", isFrozen: false});
      await db.doc(`senderWallets/${id}`).create({userId: id, balance: 49, rothCredit: 49, currency: "ROTH", status: "active"});
      await db.doc(`giftPaymentDrafts/${id}`).create({giftDraftId: id, senderId: id, senderEmail: email, recipientName: "Synthetic QA Recipient", recipientEmail: "recipient@example.invalid", deliveryAddress: "Synthetic QA London", giftMode: "gift_others", grossGiftBudget: 50, grossBudget: 50, giftCheckoutProtocol: require("./gift-checkout-reservations").VERSION, paymentStatus: "payment_pending", giftStatus: "draft", status: "draft"});
      await db.doc(`giftCheckoutOrigins/${id}`).create({senderId: id, giftDraftId: id});
      return require("./gifts-payment")._private.createGiftPaymentHandler(stripe, db)({giftDraftId: id, applyRoth: true, paymentMethod: "card", checkoutMode: "payment_intent"}, {auth: {uid: id, token: {email}}});
    }
    if (data.action === "scheduled_email") {
      const now = Date.now();
      const row = {status: "scheduled", paymentStatus: "paid", productType: "standard", fulfilmentMode: "scheduled", scheduledAt: require("firebase-admin/firestore").Timestamp.fromMillis(now - 1000), senderId: id, requestId: id, senderEmail: id + "@example.test"};
      await db.doc(`deliveryRequests/${id}`).create(row);
      const core = require("./delivery-maintenance-core");
      const activations = await Promise.all([core.activateOne(db, id, now), core.activateOne(db, id, now)]);
      const publish = require("./transactional-email-publishers").publishFromEvent;
      const input = {db, eventType: "google.cloud.firestore.document.v1.created", eventId: id, decoded: {documentName: `projects/demo-pay-cert-20261016/databases/(default)/documents/deliveryRequests/${id}`, before: {}, after: row}};
      const first = await publish(input); const duplicate = await publish(input);
      const captures = [];
      const fetchImpl = async (url, options) => {
captures.push({url, idempotencyKey: options.headers["Idempotency-Key"]}); return {ok: true, status: 200, json: async () => ({id: "cert_capture_" + id})};
};
      const processRecord = require("./cloud-run-transactional-email").processEmailQueueRecord;
      const sent = await processRecord({db, emailId: first.id, eventId: id, apiKey: "isolated-no-provider-credential", fetchImpl});
      const replay = await processRecord({db, emailId: first.id, eventId: id, apiKey: "isolated-no-provider-credential", fetchImpl});
      return {activations, first, duplicate, sent, replay, transportCaptures: captures, externalEmailsSent: 0, naturalEventarcTriggerProven: false};
    }
    if (data.action === "business_checkout") {
      await db.doc(`businessAccounts/${id}`).create({ownerUid: id, outstandingInvoiceAmount: 8});
      await db.doc(`business_wallets/${id}`).create({balance: 7, availableBalance: 7, status: "active"});
      await db.doc(`businessInvoices/${id}`).create({businessId: id, total: 8, balanceDue: 8, amountPaid: 0, status: "unpaid", checkoutProtocolVersion: 1});
      const result = await require("./business-checkout-reservations").checkout({db, stripe, invoiceId: id, businessId: id, uid: id, data: {useRoth: true, paymentAmount: 8, returnUrl: process.env.CIRCUM_CERT_ORIGIN + "/return"}});
      return result;
    }
    if (data.action === "adjustment_checkout") {
      await db.doc(`deliveryAdjustments/${id}`).create({senderId: id, bookingId: id, riderId: "cert_rider", status: "awaiting_sender_payment", adminDecision: "approve", additionalAmount: 1, revisedQuote: 9});
      await db.doc(`deliveryRequests/${id}`).create({status: "awaiting_sender_adjustment", preAdjustmentStatus: "accepted"});
      const fixtureStripe = {paymentIntents: stripe.paymentIntents, checkout: {sessions: {retrieve: (...a) => stripe.checkout.sessions.retrieve(...a), create: (params, options) => stripe.checkout.sessions.create({...params, success_url: process.env.CIRCUM_CERT_ORIGIN + "/return", cancel_url: process.env.CIRCUM_CERT_ORIGIN + "/cancel"}, options)}}};
      return require("./delivery-adjustment-checkout").createPayment({db, stripe: fixtureStripe, adjustmentId: id, senderId: id, hosted: true});
    }
    throw new Error("Unknown fixture action");
  }
  const server = http.createServer(async (req, res) => {
    const path = new URL(req.url, "http://localhost").pathname;
    const send = (status, body) => {
res.writeHead(status, {"Content-Type": "application/json", "Cache-Control": "no-store"}); res.end(JSON.stringify(body));
};
    if (path === "/health") return send(200, {certificationOnly: true, mode: "test", emulatorOnly: true, incarnation, configured: !!signingSecret, source: process.env.CIRCUM_SOURCE_SHA});
    if (["/return", "/cancel"].includes(path)) {
      res.writeHead(200, {"Content-Type": "text/html", "Cache-Control": "no-store"});
      return res.end("<title>CIRCUM isolated payment certification</title><h1>Isolated Stripe sandbox return</h1><p>This is a disposable certification fixture. Returning here never marks a payment paid.</p>");
    }
    if (req.method !== "POST" || !["/rpc", "/stripe/webhook", "/stripe/connect-webhook"].includes(path)) return send(404, {error: "not_found"});
    if (path === "/rpc") {
      const given = Buffer.from(req.headers.authorization || ""); const expected = Buffer.from("Bearer " + process.env.CIRCUM_CERT_TOKEN);
      if (given.length !== expected.length || !crypto.timingSafeEqual(given, expected)) return send(401, {error: "unauthenticated"});
    }
    let raw = Buffer.alloc(0);
    for await (const part of req) {
raw = Buffer.concat([raw, part]); if (raw.length > 1048576) return send(413, {error: "too_large"});
}
    try {
      if (path === "/rpc") return send(200, {incarnation, result: await rpc(JSON.parse(raw.toString()))});
      if (path === "/stripe/connect-webhook") {
        if (!connectHandler) return send(503, {error: "not_configured"});
        req.rawBody = raw; let code = 200;
        const finish = (body) => {
          let ev;
          try {
ev = stripe.webhooks.constructEvent(raw, req.headers["stripe-signature"], process.env.STRIPE_CONNECT_WEBHOOK_SECRET);
} catch (_) {/* canonical rejection */}
          events.push({id: ev?.id || null, type: ev?.type || null, objectId: ev?.data?.object?.id || null, livemode: ev?.livemode ?? null, signatureVerified: !!ev, status: code, stream: "connect", result: body});
          send(code, body);
        };
        return await connectHandler(req, {status(n) {
code = n; return this;
}, send: finish, json: finish});
      }
      if (!signingSecret) return send(503, {error: "not_configured"});
      const result = await processor({rawBody: raw, signature: req.headers["stripe-signature"]});
      let event;
      try {
event = stripe.webhooks.constructEvent(raw, req.headers["stripe-signature"], signingSecret);
} catch (_) {/* canonical handler rejects */}
      events.push({id: event?.id || null, type: event?.type || null, objectId: event?.data?.object?.id || null, livemode: event?.livemode ?? null, signatureVerified: !!event, status: result.status, result: result.body});
      return send(result.status, result.body);
    } catch (error) {
 return send(400, {error: String(error.message).slice(0, 220)});
}
  });
  server.listen(Number(process.env.PORT || 8080), "0.0.0.0");
  fs.writeFileSync("/tmp/certification-ready", incarnation);
}
start().catch(() => {
console.error("Isolated certification startup rejected"); process.exit(1);
});
