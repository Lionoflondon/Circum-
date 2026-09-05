/* eslint-disable max-len, require-jsdoc */
const {test, before, after} = require("node:test");
const assert = require("node:assert/strict");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {getStorage} = require("firebase-admin/storage");
const enabled =
  !!process.env.FIRESTORE_EMULATOR_HOST && !!process.env.STORAGE_EMULATOR_HOST;
let app;
let db;
let bucket;
before(() => {
  if (enabled) {
    app = initializeApp({
      projectId: "demo-lifecycle",
      storageBucket: "demo-lifecycle.appspot.com",
    });
    db = getFirestore();
    bucket = getStorage().bucket();
  }
});
after(async () => {
  if (app) await deleteApp(app);
});
const call = (...args) =>
  require("./delivery-tracking").updateDeliveryTrackingStatus.run(...args);
const context = {auth: {uid: "rider", token: {}}};
async function photo(stage) {
  const path = `delivery_weight_evidence/job/${stage}/123.jpg`;
  await bucket.file(path).save(Buffer.from("jpeg"), {
    metadata: {
      contentType: "image/jpeg",
      metadata: {
        deliveryId: "job",
        uploadedBy: "rider",
        evidenceType: "weight_discrepancy",
      },
    },
  });
  return `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(path)}?alt=media`;
}
test(
  "real lifecycle enforces assigned Rider, pickup PIN/evidence, handover and exactly-once earnings/rank",
  {skip: !enabled},
  async () => {
    await db.doc("deliveryRequests/job").set({
      senderId: "sender",
      riderId: "rider",
      status: "accepted",
      requiresVanguard: true,
      riderEarning: 6,
      paymentStatus: "paid",
    });
    await db
      .doc("deliveryRequestsPrivate/job")
      .set({collectionPin: "123456", deliveryPin: "654321"});
    await db.doc("riders/rider").set({status: "active"});
    await db
      .doc("riderProfiles/rider")
      .set({trustPoints: 98, completedDeliveries: 0});
    await assert.rejects(
      call(
        {deliveryId: "job", action: "arrived_at_pickup"},
        {auth: {uid: "other", token: {}}},
      ),
      /assigned rider/,
    );
    await call({deliveryId: "job", action: "arrived_at_pickup"}, context);
    await assert.rejects(
      call({deliveryId: "job", action: "confirm_collected"}, context),
      /collection PIN/,
    );
    await assert.rejects(
      call(
        {deliveryId: "job", action: "verify_collection_pin", pin: "123456"},
        context,
      ),
      /evidence photo/,
    );
    const pickup = {
      photoUrl: "https://example.invalid/fake.jpg",
      conditionConfirmed: true,
      riderDeclarationAccepted: true,
    };
    await assert.rejects(
      call(
        {
          deliveryId: "job",
          action: "verify_collection_pin",
          pin: "123456",
          evidence: pickup,
        },
        context,
      ),
      /Upload a photo/,
    );
    pickup.photoUrl = await photo("pickup");
    await call(
      {
        deliveryId: "job",
        action: "verify_collection_pin",
        pin: "123456",
        evidence: pickup,
      },
      context,
    );
    await call({deliveryId: "job", action: "confirm_collected"}, context);
    await call({deliveryId: "job", action: "start_delivery"}, context);
    await call({deliveryId: "job", action: "arrived_at_dropoff"}, context);
    const handover = {
      photoUrl: await photo("handover"),
      recipientConfirmed: true,
    };
    await assert.rejects(
      call(
        {
          deliveryId: "job",
          action: "verify_receiver_pin",
          pin: "000000",
          evidence: handover,
        },
        context,
      ),
      /PIN/,
    );
    await call(
      {
        deliveryId: "job",
        action: "verify_receiver_pin",
        pin: "654321",
        evidence: handover,
      },
      context,
    );
    const retry = await call(
      {
        deliveryId: "job",
        action: "verify_receiver_pin",
        pin: "654321",
        evidence: handover,
      },
      context,
    );
    assert.equal(retry.idempotent, true);
    const delivery = (await db.doc("deliveryRequests/job").get()).data();
    assert.equal(delivery.status, "delivered");
    assert.equal(delivery.handoverEvidence.recordedBy, "rider");
    assert.equal(
      (await db.doc("riderEarnings/rider").get()).data().availableBalance,
      6,
    );
    const profile = (await db.doc("riderProfiles/rider").get()).data();
    assert.equal(profile.trustPoints, 102);
    assert.equal(profile.riderRank, "sentinel");
    assert.equal(
      (await db.collection("riderEarningTransactions").get()).size,
      1,
    );
  },
);
test(
  "accepted scheduled job cannot start pickup before its scheduled time",
  {skip: !enabled},
  async () => {
    await db.doc("deliveryRequests/scheduled").set({
      riderId: "rider",
      status: "accepted",
      isScheduled: true,
      scheduledAt: Date.now() + 3600000,
    });
    await assert.rejects(
      call(
        {deliveryId: "scheduled", action: "start_heading_to_pickup"},
        context,
      ),
      /not ready for pickup/,
    );
  },
);
test(
  "old adjustment cannot cancel a completed delivery",
  {skip: !enabled},
  async () => {
    await db
      .doc("deliveryRequests/finished")
      .set({senderId: "sender", status: "completed"});
    await db
      .doc("deliveryAdjustments/old")
      .set({senderId: "sender", bookingId: "finished", status: "paid"});
    await assert.rejects(
      require("./delivery-adjustments").cancelAdjustedCollection.run(
        {adjustmentId: "old"},
        {auth: {uid: "sender", token: {}}},
      ),
      /no longer awaiting/,
    );
    assert.equal(
      (await db.doc("deliveryRequests/finished").get()).data().status,
      "completed",
    );
  },
);
test(
  "Business Roth-only and mixed Stripe finalizers debit once and reject forged sessions",
  {skip: !enabled},
  async () => {
    const business = require("./business-payments");
    const ctx = {
      auth: {
        uid: "business-owner",
        token: {email: "owner@example.invalid"},
      },
    };
    let lastSession;
    let calls = 0;
    const stripe = {
      checkout: {
        sessions: {
          list: async () => ({
            data: lastSession ? [lastSession] : [],
            has_more: false,
          }),
          retrieve: async () => lastSession,
          create: async (params) => {
            calls += 1;
            lastSession = {
              id: `cs_${calls}`,
              status: "open",
              payment_status: "unpaid",
              url: "https://example.invalid/checkout",
              payment_intent: `pi_${calls}`,
              metadata: params.metadata,
              client_reference_id: params.client_reference_id,
              currency: "gbp",
              amount_total: params.line_items[0].price_data.unit_amount,
            };
            return lastSession;
          },
        },
      },
    };
    await db.doc("businessAccounts/business").set({
      ownerUid: "business-owner",
      createdByUserId: "business-owner",
      teamMemberIds: [],
    });
    await db
      .doc("business_wallets/business")
      .set({balance: 10, status: "active"});
    await db.doc("businessInvoices/roth").set({
      businessId: "business",
      total: 5,
      balanceDue: 5,
      amountPaid: 0,
      status: "unpaid",
    });
    const checkout = business.createBusinessInvoiceCheckout(stripe);
    const paid = await checkout.run(
      {businessId: "business", invoiceId: "roth", useRoth: true},
      ctx,
    );
    assert.equal(paid.paid, true);
    assert.equal(calls, 0);
    await assert.rejects(
      checkout.run(
        {businessId: "business", invoiceId: "roth", useRoth: true},
        ctx,
      ),
      /another payment/,
    );
    assert.equal(
      (await db.doc("business_wallets/business").get()).data().balance,
      5,
    );
    await db.doc("businessInvoices/mixed").set({
      businessId: "business",
      total: 10,
      balanceDue: 10,
      amountPaid: 0,
      status: "unpaid",
    });
    const mixed = await checkout.run(
      {businessId: "business", invoiceId: "mixed", useRoth: true},
      ctx,
    );
    assert.equal(mixed.cardAmount, 5);
    assert.equal(mixed.rothApplied, 5);
    const verified = {...lastSession, payment_status: "paid"};
    await assert.rejects(
      business.handleBusinessCheckoutSession(
        {...verified, amount_total: 1},
        "fake-amount",
      ),
      /payment does not match/,
    );
    await assert.rejects(
      business.handleBusinessCheckoutSession(
        {...verified, id: "other-session"},
        "fake-session",
      ),
      /payment does not match/,
    );
    await assert.rejects(
      business.handleBusinessCheckoutSession(
        {...verified, payment_status: "unpaid"},
        "unpaid",
      ),
      /payment does not match/,
    );
    await business.handleBusinessCheckoutSession(verified, "verified");
    await business.handleBusinessCheckoutSession(verified, "retry");
    assert.equal(
      (await db.doc("business_wallets/business").get()).data().balance,
      0,
    );
    assert.equal(
      (await db.doc("businessInvoices/mixed").get()).data().amountPaid,
      10,
    );
  },
);
test(
  "Business member cannot create payment for another Business invoice",
  {skip: !enabled},
  async () => {
    await db.doc("businessInvoices/other").set({
      businessId: "other-business",
      total: 10,
      balanceDue: 10,
      status: "unpaid",
    });
    const stripe = {
      checkout: {
        sessions: {
          create: async () => {
            throw new Error("Stripe must not be called");
          },
        },
      },
    };
    await assert.rejects(
      require("./business-payments")
        .createBusinessInvoiceCheckout(stripe)
        .run(
          {businessId: "business", invoiceId: "other"},
          {auth: {uid: "business-owner", token: {}}},
        ),
      /does not belong/,
    );
  },
);
