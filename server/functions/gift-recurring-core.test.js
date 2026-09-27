const test = require("node:test");
const assert = require("node:assert/strict");
const core = require("./gift-recurring-core");
const recurring = require("./gift-recurring");

function memoryDb(seed = {}) {
  const data = new Map(Object.entries(seed));
  const ref = (path) => ({
    id: path.split("/").pop(),
    path,
    async get() {
      const value = data.get(path);
      return {exists: value !== undefined, data: () => value && {...value}};
    },
    async set(value, options = {}) {
      data.set(path, options.merge ? {...(data.get(path) || {}), ...value} : {...value});
    },
  });
  return {
    collection(name) {
      return {doc: (id) => ref(`${name}/${id}`)};
    },
    async runTransaction(work) {
      return work({
        get: (reference) => reference.get(),
        set: (reference, value, options) => reference.set(value, options),
      });
    },
    read: (path) => data.get(path),
  };
}

test("recurring frequency is explicit and maps to Stripe billing intervals", () => {
  assert.equal(core.normalizeFrequency("one_off"), "one_time");
  assert.deepEqual(core.intervalFor("monthly"), {interval: "month", interval_count: 1, label: "Monthly"});
  assert.deepEqual(core.intervalFor("quarterly"), {interval: "month", interval_count: 4, label: "Every 4 months"});
  assert.equal(core.isRecurringFrequency("one_time"), false);
});

test("series and renewal identities are deterministic", () => {
  assert.equal(core.seriesIdForGift("gift-1"), core.seriesIdForGift("gift-1"));
  assert.notEqual(core.seriesIdForGift("gift-1"), core.seriesIdForGift("gift-2"));
  assert.equal(core.renewalIdForInvoice("sub-1", "in-1"), core.renewalIdForInvoice("sub-1", "in-1"));
  assert.notEqual(core.renewalGiftIdForInvoice("sub-1", "in-1"), core.renewalGiftIdForInvoice("sub-1", "in-2"));
});

test("delivery pattern preserves the original day and never schedules in the past", () => {
  const pattern = core.buildDeliveryPattern("2026-01-15T12:00:00Z", {timeWindow: "afternoon"});
  const result = core.deliveryDateForPeriod({
    pattern,
    periodStart: "2026-02-01T00:00:00Z",
    periodEnd: "2026-03-01T00:00:00Z",
    now: "2026-02-02T00:00:00Z",
  });
  assert.equal(result.status, "scheduled");
  assert.equal(result.date, "2026-02-15T12:00:00.000Z");
  assert.equal(result.timeWindow, "afternoon");
});

test("an impossible day-of-month is action-required, never silently clamped", () => {
  const pattern = core.buildDeliveryPattern("2026-01-31T12:00:00Z");
  const result = core.deliveryDateForPeriod({
    pattern,
    periodStart: "2026-02-01T00:00:00Z",
    periodEnd: "2026-03-01T00:00:00Z",
    now: "2026-02-02T00:00:00Z",
  });
  assert.equal(result.status, "action_required");
  assert.equal(result.reason, "delivery_day_not_present_in_period");
});

test("successful renewal only accepts paid invoice state", () => {
  assert.equal(core.successfulInvoice({status: "paid"}), true);
  assert.equal(core.successfulInvoice({status: "open", paid: false}), false);
  assert.equal(core.subscriptionState("active", true), "cancellation_pending");
  assert.equal(core.subscriptionState("canceled"), "ended");
});

test("renewal invoice validation requires exact subscription, amount, currency, billing reason and period", () => {
  const series = {stripeSubscriptionId: "sub_1", stripeCustomerId: "cus_1", budgetGbp: 50};
  const invoice = {
    subscription: "sub_1",
    customer: "cus_1",
    amount_paid: 5000,
    currency: "gbp",
    billing_reason: "subscription_cycle",
    period_start: 1000,
    period_end: 2000,
  };
  assert.equal(recurring.validateRenewalInvoice(invoice, series).valid, true);
  for (const [field, value] of [["subscription", "sub_other"], ["customer", "cus_other"], ["amount_paid", 4999], ["currency", "usd"], ["billing_reason", "manual"], ["period_end", 999]]) {
    assert.equal(recurring.validateRenewalInvoice({...invoice, [field]: value}, series).valid, false, field);
  }
});

test("a recurring series in creating state recovers an already-created Stripe subscription", async () => {
  const seriesId = core.seriesIdForGift("gift-recover");
  const db = memoryDb({
    "giftRequests/gift-recover": {
      giftMode: "gift_myself",
      selfGiftFrequency: "monthly",
      grossGiftBudget: 50,
      cardAmount: 50,
      senderId: "sender-1",
      senderEmail: "sender@example.test",
      stripeCustomerId: "cus_1",
      deliveryDate: "2099-01-15T12:00:00Z",
      deliveryTimeWindow: "09:00-12:00",
      recurringConsentAccepted: true,
      paidAt: "2026-09-01T12:00:00Z",
    },
  });
  let creates = 0;
  const stripe = {
    subscriptions: {
      list: async () => ({data: [{id: "sub_recovered", status: "active", metadata: {giftRecurringSeriesId: seriesId}, current_period_start: 100, current_period_end: 200}]}),
      create: async () => {
        creates += 1;
        return {id: "sub_new", status: "active"};
      },
    },
  };
  const result = await recurring.ensureSeriesAfterInitialPayment({
    db,
    stripe,
    giftId: "gift-recover",
    payment: {customerId: "cus_1", paymentIntentId: "pi_initial", paymentMethodId: "pm_initial"},
  });
  assert.equal(result.recovered, true);
  assert.equal(result.stripeSubscriptionId, "sub_recovered");
  assert.equal(creates, 0);
  assert.equal(db.read(`giftRecurringSeries/${seriesId}`).stripeSubscriptionId, "sub_recovered");
});

test("recurring setup uses an idempotent Stripe Product for subscription pricing", async () => {
  const db = memoryDb({
    "giftRequests/gift-product": {
      giftMode: "gift_myself",
      selfGiftFrequency: "monthly",
      grossGiftBudget: 50,
      cardAmount: 50,
      senderId: "sender-1",
      senderEmail: "sender@example.test",
      deliveryDate: "2099-01-15T12:00:00Z",
      deliveryTimeWindow: "09:00-12:00",
      recurringConsentAccepted: true,
      paidAt: "2026-09-01T12:00:00Z",
    },
  });
  let productRequest;
  let subscriptionRequest;
  const stripe = {
    customers: {update: async () => ({})},
    products: {create: async (request, options) => (productRequest = {request, options}, {id: "prod_recurring"})},
    subscriptions: {
      list: async () => ({data: []}),
      create: async (request, options) => (subscriptionRequest = {request, options}, {id: "sub_product", status: "active", current_period_start: 100, current_period_end: 200}),
    },
  };
  await recurring.ensureSeriesAfterInitialPayment({
    db,
    stripe,
    giftId: "gift-product",
    payment: {customerId: "cus_product", paymentIntentId: "pi_product", paymentMethodId: "pm_product"},
  });
  assert.equal(productRequest.options.idempotencyKey, `gift_recurring_product_${core.seriesIdForGift("gift-product")}`);
  assert.equal(subscriptionRequest.request.items[0].price_data.product, "prod_recurring");
  assert.equal(Object.hasOwn(subscriptionRequest.request.items[0].price_data, "product_data"), false);
});

test("renewal validation binds the paid invoice to the approved recurring series", () => {
  const series = {
    stripeSubscriptionId: "sub_expected",
    stripeCustomerId: "cus_expected",
    budgetGbp: 50,
    currentPeriodEnd: 1800000000000,
    status: "active",
  };
  const correct = core.validateRenewalInvoice({
    series,
    subscriptionId: "sub_expected",
    invoice: {
      id: "in_correct",
      subscription: "sub_expected",
      customer: "cus_expected",
      status: "paid",
      currency: "gbp",
      amount_paid: 5000,
      billing_reason: "subscription_cycle",
      period_start: 1800000000,
      period_end: 1826000000,
    },
  });
  assert.deepEqual(correct, {ok: true, failures: []});
  for (const [field, value, expected] of [
    ["subscription", "sub_other", "subscription_mismatch"],
    ["customer", "cus_other", "customer_mismatch"],
    ["currency", "usd", "currency_mismatch"],
    ["amount_paid", 4999, "amount_mismatch"],
    ["billing_reason", "manual", "billing_reason_mismatch"],
    ["period_start", 1800000001, "billing_period_mismatch"],
  ]) {
    const invoice = {
      id: `in_${field}`,
      subscription: "sub_expected",
      customer: "cus_expected",
      status: "paid",
      currency: "gbp",
      amount_paid: 5000,
      billing_reason: "subscription_cycle",
      period_start: 1800000000,
      period_end: 1826000000,
      [field]: value,
    };
    const result = core.validateRenewalInvoice({series, subscriptionId: "sub_expected", invoice});
    assert.equal(result.ok, false, field);
    assert.ok(result.failures.includes(expected), field);
  }
});

test("renewal validation uses the Stripe subscription line period rather than the invoice trial envelope", () => {
  const invoice = {
    id: "in_trial_following_renewal",
    subscription: "sub_expected",
    customer: "cus_expected",
    status: "paid",
    currency: "gbp",
    amount_paid: 5000,
    billing_reason: "subscription_cycle",
    // Stripe's aggregate invoice envelope spans the original trial. The
    // subscription line is the authoritative paid renewal billing period.
    period_start: 1790518084,
    period_end: 1801058886,
    lines: {data: [
      {type: "subscription", proration: false, period: {start: 1801058886, end: 1811426886}},
    ]},
  };
  const result = core.validateRenewalInvoice({
    series: {stripeSubscriptionId: "sub_expected", stripeCustomerId: "cus_expected", budgetGbp: 50, currentPeriodEnd: 1801058886000, status: "active"},
    subscriptionId: "sub_expected",
    invoice,
  });
  assert.deepEqual(result, {ok: true, failures: []});
  assert.deepEqual(core.invoiceBillingPeriod(invoice), {start: 1801058886, end: 1811426886});
  const localResult = recurring.validateRenewalInvoice(invoice, {
    stripeSubscriptionId: "sub_expected", stripeCustomerId: "cus_expected", budgetGbp: 50, currentPeriodEnd: 1801058886000,
  });
  assert.equal(localResult.valid, true);
  assert.deepEqual(localResult.reasons, []);
});

test("renewal period extraction ignores prorations and falls back only when subscription lines are absent", () => {
  const invoice = {
    period_start: 1801058886,
    period_end: 1811426886,
    lines: {data: [
      {type: "subscription", proration: true, period: {start: 1801058886, end: 1801060000}},
      {type: "subscription", proration: false, period: {start: 1801058886, end: 1811426886}},
    ]},
  };
  assert.deepEqual(core.invoiceBillingPeriod(invoice), {start: 1801058886, end: 1811426886});
  assert.deepEqual(core.invoiceBillingPeriod({period_start: 10, period_end: 20}), {start: 10, end: 20});
});

test("next renewal advances by the actual Stripe interval and preserves a safe month boundary", () => {
  assert.equal(
      new Date(core.nextRenewalAt({from: "2026-01-31T12:00:00Z", frequency: "monthly"})).toISOString(),
      "2026-02-28T12:00:00.000Z",
  );
  assert.equal(
      new Date(core.nextRenewalAt({from: "2026-01-15T12:00:00Z", frequency: "quarterly"})).toISOString(),
      "2026-05-15T12:00:00.000Z",
  );
});
