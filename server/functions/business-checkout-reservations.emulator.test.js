/* eslint-disable max-len, require-jsdoc */
const {test, before, after} = require("node:test");
const assert = require("node:assert/strict");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const core = require("./business-checkout-reservations");
const enabled = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
let db;
let app;
before(() => {
  if (enabled) {
    app = initializeApp({projectId: "demo-business-reservations"});
    db = getFirestore();
  }
});
after(async () => {
  if (app) await deleteApp(app);
});
function provider() {
  const sessions = new Map();
  const keys = new Map();
  let objects = 0;
  let failAfterCreate = false;
  const stripe = {
    checkout: {
      sessions: {
        list: async () => ({data: [...sessions.values()], has_more: false}),
        retrieve: async (id) => {
          assert.ok(sessions.has(id));
          return {...sessions.get(id)};
        },
        create: async (params, options) => {
          assert.ok(options.idempotencyKey);
          const key = options.idempotencyKey;
          if (keys.has(key)) {
            assert.deepEqual(keys.get(key).params, params);
            return {...sessions.get(keys.get(key).id)};
          }
          const id = `cs_${++objects}`;
          const s = {
            id,
            url: `https://example.invalid/${id}`,
            status: "open",
            payment_status: "unpaid",
            payment_intent: `pi_${objects}`,
            metadata: params.metadata,
            currency: params.line_items[0].price_data.currency,
            amount_total: params.line_items[0].price_data.unit_amount,
          };
          sessions.set(id, s);
          keys.set(key, {id, params});
          if (failAfterCreate) {
            failAfterCreate = false;
            throw new Error("network timeout after provider accepted request");
          }
          return {...s};
        },
        expire: async (id) => {
          const s = sessions.get(id);
          assert.notEqual(s.payment_status, "paid");
          s.status = "expired";
          return {...s};
        },
      },
    },
  };
  return {
    stripe,
    sessions,
    objects: () => objects,
    ambiguousFailure: () => {
      failAfterCreate = true;
    },
  };
}
async function fixture(id, balance = 7, amount = 20, legacy = false) {
  await db
    .doc(`businessAccounts/${id}`)
    .set({ownerUid: "owner", teamMemberIds: ["member-a", "member-b"]});
  await db
    .doc(`business_wallets/${id}`)
    .set({balance, availableBalance: balance, status: "active"});
  await db.doc(`businessInvoices/${id}`).set({
    businessId: id,
    total: amount,
    balanceDue: amount,
    amountPaid: 0,
    status: "unpaid",
    ...(legacy ? {} : {checkoutProtocolVersion: 1}),
  });
}
function checkout(id, p, data = {}, uid = "owner") {
  return core.checkout({
    db,
    stripe: p.stripe,
    invoiceId: id,
    businessId: id,
    uid,
    data: {useRoth: true, ...data},
  });
}
test(
  "concurrent devices and Business members share one £7 hold and one £13 provider object",
  {skip: !enabled},
  async () => {
    const id = "concurrent";
    await fixture(id);
    const p = provider();
    const results = await Promise.all(
      Array.from({length: 12}, (_, i) =>
        checkout(id, p, {paymentAmount: 20}, i % 2 ? "member-a" : "member-b"),
      ),
    );
    assert.equal(new Set(results.map((r) => r.checkoutReservationId)).size, 1);
    assert.equal(new Set(results.map((r) => r.sessionId)).size, 1);
    assert.equal(p.objects(), 1);
    const w = (await db.doc(`business_wallets/${id}`).get()).data();
    assert.equal(w.balance, 7);
    assert.equal(w.reservedBalance, 7);
    assert.equal(w.availableBalance, 0);
    assert.equal(results[0].cardAmount, 13);
    await assert.rejects(
      checkout(id, p, {paymentAmount: 0.01}),
      /balance changed/,
    );
    assert.equal(p.objects(), 1);
    const retry = await checkout(id, p);
    assert.equal(retry.sessionId, results[0].sessionId);
  },
);
test(
  "a second invoice cannot promise Roth already held by the first checkout",
  {skip: !enabled},
  async () => {
    const id = "contention";
    await fixture(id);
    const p = provider();
    await db.doc(`businessInvoices/${id}-second`).set({
      businessId: id,
      total: 20,
      balanceDue: 20,
      status: "unpaid",
      checkoutProtocolVersion: 1,
    });
    const a = await checkout(id, p);
    const b = await core.checkout({
      db,
      stripe: p.stripe,
      invoiceId: `${id}-second`,
      businessId: id,
      uid: "owner",
      data: {useRoth: true},
    });
    assert.equal(a.rothApplied, 7);
    assert.equal(b.rothApplied, 0);
    assert.equal(b.cardAmount, 20);
    const wallet = (await db.doc(`business_wallets/${id}`).get()).data();
    assert.equal(wallet.reservedBalance, 7);
    await assert.rejects(
      require("./business-payments")._private.debitBusinessRoth({
        businessId: id,
        amount: 1,
        invoiceId: "elsewhere",
        metadata: {paymentId: "other"},
      }),
      /too low/,
    );
  },
);
test(
  "ambiguous create failure reuses persisted provider key without releasing Roth",
  {skip: !enabled},
  async () => {
    const id = "network";
    await fixture(id);
    const p = provider();
    p.ambiguousFailure();
    await assert.rejects(checkout(id, p), /network timeout/);
    assert.equal(
      (await db.doc(`business_wallets/${id}`).get()).data().reservedBalance,
      7,
    );
    const retried = await checkout(id, p);
    assert.equal(retried.sessionId, "cs_1");
    assert.equal(p.objects(), 1);
  },
);
test(
  "confirmed cancellation releases once and permits a new generation",
  {skip: !enabled},
  async () => {
    const id = "cancel";
    await fixture(id);
    const p = provider();
    const a = await checkout(id, p);
    const reservation = (
      await db
        .doc(`businessCheckoutReservations/${a.checkoutReservationId}`)
        .get()
    ).data();
    await Promise.all([
      core.terminate({db, stripe: p.stripe, reservation}),
      core.terminate({db, stripe: p.stripe, reservation}),
    ]);
    const w = (await db.doc(`business_wallets/${id}`).get()).data();
    assert.equal(w.reservedBalance, 0);
    assert.equal(w.balance, 7);
    assert.equal(w.availableBalance, 7);
    const b = await checkout(id, p);
    assert.notEqual(a.checkoutReservationId, b.checkoutReservationId);
    assert.equal(p.objects(), 2);
    assert.equal(
      [...p.sessions.values()].filter((s) => s.status === "open").length,
      1,
    );
  },
);
test(
  "provider expiry permits a new generation; a clock timeout alone cannot release",
  {skip: !enabled},
  async () => {
    const id = "expire";
    await fixture(id);
    const p = provider();
    const a = await checkout(id, p);
    await assert.rejects(
      core.release({db, id: a.checkoutReservationId, status: "expired"}),
      /not been confirmed/,
    );
    p.sessions.get(a.sessionId).status = "expired";
    const b = await checkout(id, p);
    assert.notEqual(a.sessionId, b.sessionId);
    assert.equal(p.objects(), 2);
    assert.equal(
      (await db.doc(`business_wallets/${id}`).get()).data().reservedBalance,
      7,
    );
  },
);
test(
  "verified success captures reserved Roth once under concurrent finalizers",
  {skip: !enabled},
  async () => {
    const id = "success";
    await fixture(id);
    const p = provider();
    const a = await checkout(id, p);
    const session = {
      ...p.sessions.get(a.sessionId),
      status: "complete",
      payment_status: "paid",
    };
    await assert.rejects(
      core.settle({
        db,
        id: a.checkoutReservationId,
        session: {...session, amount_total: 1},
      }),
      /does not match/,
    );
    await assert.rejects(
      core.settle({
        db,
        id: a.checkoutReservationId,
        session: {...session, currency: "usd"},
      }),
      /does not match/,
    );
    await Promise.all(
      Array.from({length: 8}, () =>
        core.settle({db, id: a.checkoutReservationId, session}),
      ),
    );
    const w = (await db.doc(`business_wallets/${id}`).get()).data();
    assert.equal(w.balance, 0);
    assert.equal(w.reservedBalance, 0);
    assert.equal(w.lifetimeSpent, 7);
    assert.equal(
      (await db.doc(`businessInvoices/${id}`).get()).data().balanceDue,
      0,
    );
    const debits = await db
      .collection(`business_wallets/${id}/transactions`)
      .where("direction", "==", "debit")
      .get();
    assert.equal(debits.size, 1);
    await assert.rejects(checkout(id, p), /another payment/);
    assert.equal(p.objects(), 1);
  },
);
test(
  "paid and zero invoices cannot reserve or create a provider object",
  {skip: !enabled},
  async () => {
    const p = provider();
    for (const status of ["paid", "unpaid"]) {
      const id = `zero-${status}`;
      await fixture(id, 7, 0);
      await db.doc(`businessInvoices/${id}`).update({status});
      await assert.rejects(checkout(id, p), /another payment/);
    }
    assert.equal(p.objects(), 0);
  },
);
test(
  "legacy open and orphaned provider checkouts expire before regeneration",
  {skip: !enabled},
  async () => {
    const id = "legacy";
    await fixture(id, 7, 20, true);
    const p = provider();
    p.sessions.set("legacy-orphan", {
      id: "legacy-orphan",
      status: "open",
      payment_status: "unpaid",
      metadata: {
        type: "business_invoice_payment",
        businessId: id,
        invoiceId: id,
      },
    });
    const a = await checkout(id, p);
    assert.ok(a.sessionId);
    assert.equal(p.sessions.get("legacy-orphan").status, "expired");
    assert.equal(
      (await db.doc(`businessInvoices/${id}`).get()).data()
        .checkoutProtocolVersion,
      1,
    );
  },
);
test(
  "unreconciled paid legacy session blocks a new payable object",
  {skip: !enabled},
  async () => {
    const id = "legacy-paid";
    await fixture(id, 7, 20, true);
    const p = provider();
    p.sessions.set("old-paid", {
      id: "old-paid",
      status: "complete",
      payment_status: "paid",
      metadata: {
        type: "business_invoice_payment",
        businessId: id,
        invoiceId: id,
      },
    });
    await assert.rejects(checkout(id, p), /earlier payment/);
    assert.equal(p.objects(), 0);
  },
);
test(
  "two authenticated Business members share a checkout; non-members and forged Business ID are denied",
  {skip: !enabled},
  async () => {
    const id = "auth-members";
    await fixture(id);
    const p = provider();
    const callable =
      require("./business-payments").createBusinessInvoiceCheckout(p.stripe);
    const results = await Promise.all(
      ["member-a", "member-b"].map((uid) =>
        callable.run({invoiceId: id, useRoth: true}, {auth: {uid, token: {}}}),
      ),
    );
    assert.equal(results[0].sessionId, results[1].sessionId);
    assert.equal(p.objects(), 1);
    await assert.rejects(
      callable.run({invoiceId: id}, {auth: {uid: "stranger", token: {}}}),
      /access/,
    );
    await assert.rejects(
      callable.run(
        {invoiceId: id, businessId: "forged"},
        {auth: {uid: "member-a", token: {}}},
      ),
      /does not belong/,
    );
  },
);
test(
  "road-charge refund preserves an active Business checkout hold and credits once",
  {skip: !enabled},
  async () => {
    const id = "refund-hold";
    await fixture(id);
    const p = provider();
    await checkout(id, p);
    const refunds = require("./scheduled-road-charge-refunds");
    await db.doc("roadChargeRefundEntitlements/refund-hold").set({
      policyVersion: refunds.REFUND_POLICY_VERSION,
      state: refunds.STATES.eligible,
      deliveryId: "job",
      quoteId: "quote",
      chargeId: "charge",
      refundablePence: 300,
      refundOwnerType: "business",
      refundOwnerId: id,
    });
    const results = await Promise.all(
      [1, 2].map(() =>
        refunds.settleEntitlementToRoth({db, entitlementId: "refund-hold"}),
      ),
    );
    assert.equal(results.filter((r) => r.settled).length, 1);
    const w = (await db.doc(`business_wallets/${id}`).get()).data();
    assert.equal(w.balance, 10);
    assert.equal(w.reservedBalance, 7);
    assert.equal(w.availableBalance, 3);
  },
);

test(
  "background expiry releases abandoned holds once without creating a replacement checkout",
  {skip: !enabled},
  async () => {
    const id = "abandoned";
    await fixture(id);
    const p = provider();
    const created = await checkout(id, p);
    await db
      .doc(`businessCheckoutReservations/${created.checkoutReservationId}`)
      .update({expiresAt: Date.now() - 1});
    const first = await core.reconcileExpired({db, stripe: p.stripe});
    const second = await core.reconcileExpired({db, stripe: p.stripe});
    assert.ok(first.scanned >= 1);
    assert.equal(
      second.results.filter(
        (r) => r.checkoutReservationId === created.checkoutReservationId,
      ).length,
      0,
    );
    assert.equal(p.objects(), 1);
    assert.equal(p.sessions.get(created.sessionId).status, "expired");
    const wallet = (await db.doc(`business_wallets/${id}`).get()).data();
    assert.equal(wallet.balance, 7);
    assert.equal(wallet.reservedBalance, 0);
    assert.equal(wallet.availableBalance, 7);
  },
);
