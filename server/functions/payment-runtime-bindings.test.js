/* eslint-disable max-len */
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const admin = require("firebase-admin");
process.env.GCLOUD_PROJECT = "demo-payment-runtime";
if (!admin.apps.length) admin.initializeApp({projectId: "demo-payment-runtime"});

const modules = {
  "business-payments": require("./business-payments"),
  "sender-finance": require("./sender-finance"),
  "sender-booking": require("./sender-booking"),
  "gifts-payment": require("./gifts-payment"),
};
const injected = {
  "business-payments": ["createBusinessInvoiceCheckout", "cancelBusinessInvoiceCheckout", "reconcileBusinessInvoiceCheckouts"],
  "sender-finance": ["listSenderPaymentMethods", "createSenderSetupIntent", "detachSenderPaymentMethod", "setDefaultSenderPaymentMethod"],
  "sender-booking": ["createSenderPaymentSession", "createSenderPaidDelivery", "finalizeSenderWebCheckout"],
  "gifts-payment": ["createGiftPayment", "finalizeGiftPayment"],
};
function secretKeys(fn) {
  return (fn.__endpoint.secretEnvironmentVariables || []).map((item) => item.key);
}
for (const [moduleName, names] of Object.entries(injected)) {
  for (const name of names) {
    test(`${name} declares the provider secret without invoking the provider`, () => {
      const stripe = new Proxy({}, {get() {
 throw new Error("Provider must remain lazy");
}});
      const fn = modules[moduleName][name](stripe);
      assert.ok(secretKeys(fn).includes("STRIPE_SECRET_KEY"));
    });
  }
}
for (const name of ["createHealthPlusBooking", "createHealthPlusCheckoutSession"]) {
  test(`${name} preserves route authority secret alongside payment binding`, () => {
    const keys = secretKeys(require("./health-plus")[name]);
    assert.deepEqual(keys.sort(), ["GOOGLE_MAPS_DIRECTIONS_API_KEY", "STRIPE_SECRET_KEY"]);
    assert.ok(!keys.includes("GOOGLE_ROUTES_API_KEY"));
  });
}
for (const name of ["createDeliveryAdjustmentPayment", "finalizeDeliveryAdjustmentPayment"]) {
  test(`${name} binds the payment provider secret`, () => {
    assert.deepEqual(secretKeys(require("./delivery-adjustments")[name]), ["STRIPE_SECRET_KEY"]);
  });
}
test("webhook retains signing secret and explicitly binds the provider key", () => {
  const source = fs.readFileSync(path.join(__dirname, "index.js"), "utf8");
  assert.match(source, /exports\.StripeWebhook = functions\s*\.runWith\(\{secrets: \[stripeWebhookSecret, "STRIPE_SECRET_KEY"\]\}\)/);
});
test("non-payment Sender functions do not inherit a Stripe secret", () => {
  const booking = require("./sender-booking");
  assert.deepEqual(secretKeys(booking.getSenderRothBalance), []);
  assert.deepEqual(secretKeys(require("./sender-finance").saveSenderCheckoutPreference), []);
  assert.deepEqual(secretKeys(booking.getSenderRoutePreview), ["GOOGLE_MAPS_DIRECTIONS_API_KEY"]);
});
