"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");

const read = (name) => fs.readFileSync(name, "utf8");

test("QA wallet references cannot point to live wallet collections", () => {
  const {walletRefsForSender} = require("./sender-booking")._private;
  const ref = (path = "") => ({
    path,
    collection: (name) => ref(path ? `${path}/${name}` : name),
    doc: (id) => ref(`${path}/${id}`),
  });
  const sender = {uid: "qa_sender", email: "sender@example.invalid"};
  const fixtureId = "a".repeat(64);
  const qa = walletRefsForSender(ref(), sender, {fixtureId, isSyntheticQa: true});
  for (const key of ["walletRef", "senderWalletRef", "walletTransactions"]) {
    assert.ok(qa[key].path.startsWith(`qaSpecialFlowFixtures/${fixtureId}/`));
  }
  const live = walletRefsForSender(ref(), sender);
  assert.equal(live.walletRef.path, "wallets/sender@example.invalid");
  assert.equal(live.senderWalletRef.path, "senderWallets/qa_sender");
  assert.equal(live.walletTransactions.path, "walletTransactions");
  assert.throws(() => walletRefsForSender(ref(), sender, {fixtureId: "forged", isSyntheticQa: true}));
});

test("Sender QA payment actions stay on the private special-flow boundary", () => {
  const qa = read("qa-special-flow.js");
  assert.match(qa, /sender_capability/);
  assert.match(qa, /sender_quote/);
  assert.match(qa, /sender_roth_prepare/);
  assert.match(qa, /sender_roth_balance/);
  assert.match(qa, /sender_payment_session/);
  assert.match(qa, /sender_finalize/);
  assert.match(qa, /senderBooking\.createSenderPaymentSession/);
  assert.match(qa, /senderBooking\.finalizeSenderCheckoutSession/);
  assert.match(qa, /qaContext/);
  assert.match(qa, /senderBooking\.cleanupQaSenderFixture/);
  assert.match(qa, /qaRoth\.seed/);
  assert.match(qa, /data\.action === "sender_capability"/);
  assert.match(qa, /return \{enabled: false\}/);
});

test("Sender QA payment reuses canonical finalization and suppresses dispatch", () => {
  const sender = read("sender-booking.js");
  assert.match(sender, /exports\._qa\s*=\s*\{/);
  assert.match(sender, /finalizeSenderCheckoutSession,/);
  assert.match(sender, /createPaidDeliveryFromSession,/);
  assert.match(sender, /qaContext \? \{closestRiders: \[\], suppressed: true\}/);
  assert.match(sender, /dispatchStatus: qaContext \? "suppressed_qa"/);
  assert.match(sender, /isSyntheticQa: true/);
  assert.match(sender, /excludeFromSettlement: true/);
  assert.match(sender, /excludeFromPayout: true/);
});

test("QA Stripe adapter accepts Sender checkout only as TEST-routed metadata", () => {
  const provider = read("qa-special-provider.js");
  assert.match(provider, /sender_delivery_payment/);
  assert.match(provider, /type: ROUTING_TYPE/);
  assert.match(provider, /qaFixtureId: fixtureId/);
  assert.match(provider, /sk_test_/);
  assert.doesNotMatch(provider, /sk_live_/);
});
