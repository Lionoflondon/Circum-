/* eslint-disable require-jsdoc */
"use strict";

const crypto = require("node:crypto");

const CONSENT_COPY = "Make this Gift recurring. By continuing, you agree that CIRCUM will automatically charge your saved payment card for the same Gift budget on each selected renewal date until you cancel. Each successful renewal creates a new Gift using your original delivery-date pattern. Roth applies only to your first payment and is not used for future renewals. You can cancel future renewals before the next billing date. Cancellation takes effect at the end of the current billing period.";
const FREQUENCIES = Object.freeze({
  monthly: Object.freeze({interval: "month", interval_count: 1, label: "Monthly"}),
  quarterly: Object.freeze({interval: "month", interval_count: 4, label: "Every 4 months"}),
});

function text(value) {
  return `${value || ""}`.trim();
}

function normalizeFrequency(value) {
  const normalized = text(value).toLowerCase();
  if (["monthly", "month"].includes(normalized)) return "monthly";
  if (["quarterly", "quarter", "every_4_months"].includes(normalized)) return "quarterly";
  return "one_time";
}

function intervalFor(value) {
  const frequency = normalizeFrequency(value);
  return FREQUENCIES[frequency] || null;
}

function isRecurringFrequency(value) {
  return Boolean(intervalFor(value));
}

function seriesIdForGift(giftId) {
  return `gift_series_${crypto.createHash("sha256").update(text(giftId)).digest("hex").slice(0, 32)}`;
}

function renewalIdForInvoice(subscriptionId, invoiceId) {
  return `renewal_${crypto.createHash("sha256").update(`${text(subscriptionId)}:${text(invoiceId)}`).digest("hex").slice(0, 40)}`;
}

function renewalGiftIdForInvoice(subscriptionId, invoiceId) {
  return `gift_${crypto.createHash("sha256").update(`gift:${text(subscriptionId)}:${text(invoiceId)}`).digest("hex").slice(0, 40)}`;
}

function toDate(value) {
  if (value instanceof Date) return new Date(value.getTime());
  if (value && typeof value.toDate === "function") return value.toDate();
  if (value && typeof value.seconds === "number") return new Date(value.seconds * 1000);
  if (typeof value === "number") return new Date(value > 1e12 ? value : value * 1000);
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function utcDateParts(value) {
  const date = toDate(value);
  if (!date) return null;
  return {year: date.getUTCFullYear(), month: date.getUTCMonth() + 1, day: date.getUTCDate()};
}

function daysInMonth(year, month) {
  return new Date(Date.UTC(year, month, 0)).getUTCDate();
}

function addMonths(year, month, count) {
  const zeroBased = year * 12 + (month - 1) + count;
  return {year: Math.floor(zeroBased / 12), month: (zeroBased % 12 + 12) % 12 + 1};
}

function buildDeliveryPattern(deliveryDate, {timezone = "Europe/London", timeWindow = "", flexible = false} = {}) {
  const parts = utcDateParts(deliveryDate);
  if (!parts) return {valid: false, reason: "missing_original_delivery_date"};
  return {
    valid: true,
    dayOfMonth: parts.day,
    month: parts.month,
    timezone: text(timezone) || "Europe/London",
    timeWindow: text(timeWindow),
    flexible: flexible === true,
    policy: "exact_day_or_action_required",
  };
}

function deliveryDateForPeriod({pattern, periodStart, periodEnd, now = new Date()}) {
  if (!pattern || pattern.valid !== true || !Number.isInteger(pattern.dayOfMonth)) {
    return {status: "action_required", reason: "invalid_delivery_pattern"};
  }
  const start = toDate(periodStart);
  const end = toDate(periodEnd);
  const floor = toDate(now) || new Date();
  if (!start || !end || end <= start) return {status: "action_required", reason: "invalid_billing_period"};
  const candidateMonth = {year: start.getUTCFullYear(), month: start.getUTCMonth() + 1};
  let target = candidateMonth;
  const maxDate = new Date(Math.max(start.getTime(), floor.getTime()));
  if (maxDate.getUTCFullYear() > target.year || (maxDate.getUTCFullYear() === target.year && maxDate.getUTCMonth() + 1 > target.month)) {
    target = addMonths(target.year, target.month, 1);
  }
  const maxDay = daysInMonth(target.year, target.month);
  if (pattern.dayOfMonth > maxDay) {
    return {status: "action_required", reason: "delivery_day_not_present_in_period", requestedDay: pattern.dayOfMonth, year: target.year, month: target.month};
  }
  const result = new Date(Date.UTC(target.year, target.month - 1, pattern.dayOfMonth, 12, 0, 0));
  if (result < floor || result >= end) {
    target = addMonths(target.year, target.month, 1);
    const nextMaxDay = daysInMonth(target.year, target.month);
    if (pattern.dayOfMonth > nextMaxDay) return {status: "action_required", reason: "delivery_day_not_present_after_period", requestedDay: pattern.dayOfMonth, year: target.year, month: target.month};
    const next = new Date(Date.UTC(target.year, target.month - 1, pattern.dayOfMonth, 12, 0, 0));
    if (next < floor) return {status: "action_required", reason: "delivery_date_in_past"};
    return {status: "scheduled", date: next.toISOString(), timezone: pattern.timezone, timeWindow: pattern.timeWindow};
  }
  return {status: "scheduled", date: result.toISOString(), timezone: pattern.timezone, timeWindow: pattern.timeWindow};
}

function nextRenewalAt({from, frequency}) {
  const source = toDate(from);
  const interval = intervalFor(frequency);
  if (!source || !interval) return null;
  const target = addMonths(source.getUTCFullYear(), source.getUTCMonth() + 1, interval.interval_count);
  const day = Math.min(source.getUTCDate(), daysInMonth(target.year, target.month));
  return new Date(Date.UTC(target.year, target.month - 1, day, source.getUTCHours(), source.getUTCMinutes(), source.getUTCSeconds())).getTime();
}

function successfulInvoice(invoice = {}) {
  return text(invoice.status).toLowerCase() === "paid" || invoice.paid === true || text(invoice.payment_status).toLowerCase() === "paid";
}

function subscriptionState(status, cancelAtPeriodEnd = false) {
  const normalized = text(status).toLowerCase();
  if (cancelAtPeriodEnd && ["active", "trialing", "past_due"].includes(normalized)) return "cancellation_pending";
  if (["active", "trialing"].includes(normalized)) return "active";
  if (["past_due", "unpaid", "incomplete"].includes(normalized)) return normalized;
  if (["canceled", "incomplete_expired"].includes(normalized)) return "ended";
  return "action_required";
}

module.exports = {
  CONSENT_COPY,
  FREQUENCIES,
  addMonths,
  buildDeliveryPattern,
  daysInMonth,
  deliveryDateForPeriod,
  intervalFor,
  isRecurringFrequency,
  nextRenewalAt,
  normalizeFrequency,
  renewalGiftIdForInvoice,
  renewalIdForInvoice,
  seriesIdForGift,
  subscriptionState,
  successfulInvoice,
  toDate,
};
