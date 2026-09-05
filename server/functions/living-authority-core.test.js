/* eslint-disable max-len, require-jsdoc */
const test = require("node:test");
const assert = require("node:assert/strict");
const {verifyDeliveryEvidence} = require("./delivery-evidence-authority");
const {healthRouteDistance} = require("./health-route-authority");
const {parcelSafety, quotePayload, assertDeliveryMatchesQuote} =
  require("./sender-booking")._private;
const url =
  "https://firebasestorage.googleapis.com/v0/b/test-bucket/o/delivery_weight_evidence%2Fjob%2Fpickup%2F123.jpg?alt=media";
const metadata = {
  contentType: "image/jpeg",
  size: "100",
  metadata: {
    deliveryId: "job",
    uploadedBy: "rider",
    evidenceType: "weight_discrepancy",
  },
};
const bucket = (meta = metadata) => ({
  name: "test-bucket",
  file: () => ({getMetadata: async () => [meta]}),
});
test("evidence requires an existing canonical upload for the delivery, stage and Rider", async () => {
  const args = {
    photoUrl: url,
    deliveryId: "job",
    riderId: "rider",
    stage: "pickup",
    bucket: bucket(),
  };
  assert.equal(
    await verifyDeliveryEvidence(args),
    "delivery_weight_evidence/job/pickup/123.jpg",
  );
  for (const patch of [
    {photoUrl: "https://example.invalid/fake.jpg"},
    {riderId: "other"},
    {deliveryId: "other"},
    {stage: "handover"},
    {bucket: bucket({...metadata, contentType: "text/html"})},
    {bucket: bucket({...metadata, size: "15728641"})},
    {
      bucket: {
        name: "test-bucket",
        file: () => ({
          getMetadata: async () => {
            throw new Error("missing");
          },
        }),
      },
    },
  ]) {
    await assert.rejects(verifyDeliveryEvidence({...args, ...patch}));
  }
});
test("Health+ distance comes from the server route for the submitted addresses", async () => {
  const calls = [];
  const fetchImpl = async (u) => {
    calls.push(u);
    return {
      ok: true,
      json: async () => ({
        status: "OK",
        routes: [{legs: [{distance: {value: 3218.688}}]}],
      }),
    };
  };
  for (const distanceMiles of [0.1, 20]) {
    assert.equal(
      await healthRouteDistance({
        pharmacyAddress: "Pharmacy",
        deliveryAddress: "Home",
        distanceMiles,
        apiKey: "test",
        fetchImpl,
      }),
      2,
    );
  }
  assert.equal(calls[0].searchParams.get("origin"), "Pharmacy");
  await assert.rejects(
    healthRouteDistance({
      pharmacyAddress: "A",
      deliveryAddress: "B",
      apiKey: "test",
      fetchImpl: async () => ({
        ok: true,
        json: async () => ({status: "ZERO_RESULTS", routes: []}),
      }),
    }),
  );
});
test("unsafe parcels fail before payment and 50kg needs manual heavy handling", () => {
  assert.throws(
    () =>
      parcelSafety({
        parcel: {description: "loaded firearm and ammunition", weightKg: 2},
      }),
    /review before payment/,
  );
  assert.throws(
    () => parcelSafety({parcel: {description: "suitcase", weightKg: 50}}),
    /review before payment/,
  );
  assert.equal(
    parcelSafety({parcel: {description: "suitcase", weightKg: 23}}).weightKg,
    23,
  );
});
test("client cannot claim free mandatory Vanguard or switch the parcel after quoting", () => {
  const q = quotePayload(
    {
      parcel: {description: "book", weightKg: 1},
      distanceMiles: 2,
      vanguard: true,
      iris: {vanguardRequired: true},
    },
    "sender",
  );
  assert.equal(q.lineItems.find((i) => i.key === "vanguard").amount, 1.99);
  q.route = {
    origin: {latitude: 51, longitude: 0},
    destination: {latitude: 52, longitude: 0},
  };
  const d = {
    pickup: q.route.origin,
    dropoff: q.route.destination,
    recipient: {name: "Recipient"},
    parcel: {description: "book", weightKg: 1},
  };
  assert.doesNotThrow(() => assertDeliveryMatchesQuote(d, q));
  assert.throws(
    () =>
      assertDeliveryMatchesQuote(
        {...d, parcel: {description: "book", weightKg: 23}},
        q,
      ),
    /changed/,
  );
  assert.throws(
    () =>
      assertDeliveryMatchesQuote(
        {...d, parcel: {description: "suitcase", weightKg: 1}},
        q,
      ),
    /changed/,
  );
});
test("adjustment Stripe payment must match amount, currency, customer and approved booking", () => {
  const {verifiedAdjustmentPayment} = require("./delivery-adjustment-core");
  const adjustment = {
    additionalAmount: 5,
    bookingId: "job",
    senderId: "sender",
  };
  const intent = {
    status: "succeeded",
    currency: "gbp",
    amount: 500,
    amount_received: 500,
    metadata: {
      feature: "delivery_adjustment",
      adjustmentId: "adjustment",
      bookingId: "job",
      senderId: "sender",
    },
  };
  assert.equal(
    verifiedAdjustmentPayment(intent, adjustment, "adjustment"),
    true,
  );
  for (const patch of [
    {amount: 1},
    {amount_received: 1},
    {currency: "usd"},
    {status: "requires_payment_method"},
    {metadata: {...intent.metadata, senderId: "other"}},
    {metadata: {...intent.metadata, adjustmentId: "other"}},
  ]) {
    assert.equal(
      verifiedAdjustmentPayment(
        {...intent, ...patch},
        adjustment,
        "adjustment",
      ),
      false,
    );
  }
});

test("minimal offer preserves the canonical estimated earning without exposing customer fare", () => {
  const offer = require("./rider-offers").projection("job", {estimatedEarnings: 6, price: 20, senderId: "private", pickupLocality: "Camden", dropoffLocality: "Islington"}, Date.now() + 30000);
  assert.equal(offer.riderEarning, 6);
  assert.equal(offer.pickupLocality, "Camden");
  assert.equal(offer.price, undefined);
  assert.equal(offer.senderId, undefined);
});
