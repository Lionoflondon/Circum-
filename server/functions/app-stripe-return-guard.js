/* eslint-disable require-jsdoc */
"use strict";

const SENDER_APP_ORIGIN = "https://circum-app-2797c.web.app";
const SENDER_APP_HOME = `${SENDER_APP_ORIGIN}/#/sender-mobile`;
const LOCAL_ORIGIN_PATTERN = /^https:\/\/(localhost(?::\d+)?|127\.0\.0\.1(?::\d+)?)$/u;

function normalizeOrigin(value, fallback = SENDER_APP_ORIGIN) {
  const origin = `${value || fallback}`.trim().replace(/\/+$/, "");
  if (origin === SENDER_APP_ORIGIN || LOCAL_ORIGIN_PATTERN.test(origin)) {
    return origin;
  }
  return fallback;
}

function normalizeSenderAppReturnBase(value, fallbackPath = "/#/sender-mobile") {
  const fallback = `${SENDER_APP_ORIGIN}${fallbackPath}`;
  const raw = `${value || fallback}`.trim();
  if (!raw) return fallback;
  let url;
  try {
    url = new URL(raw);
  } catch (_) {
    return fallback;
  }
  if (url.origin === SENDER_APP_ORIGIN || LOCAL_ORIGIN_PATTERN.test(url.origin)) {
    return raw.replace(/\/+$/, "");
  }
  return fallback;
}

function separatorFor(url) {
  return url.includes("?") ? "&" : "?";
}

function encodeQueryValue(value) {
  if (`${value}` === "{CHECKOUT_SESSION_ID}") return "{CHECKOUT_SESSION_ID}";
  return encodeURIComponent(`${value}`);
}

function queryString(params = {}) {
  return Object.entries(params)
      .filter(([, entry]) => entry !== undefined && entry !== null && `${entry}`.trim() !== "")
      .map(([key, entry]) => `${encodeURIComponent(key)}=${encodeQueryValue(entry)}`)
      .join("&");
}

function senderAppCancelUrl(value, params = {}) {
  const base = normalizeSenderAppReturnBase(value, "/#/sender-mobile");
  const query = queryString(params);
  return query ? `${base}${separatorFor(base)}${query}` : base;
}

function senderAppCheckoutUrls({
  returnUrl,
  successPath = "/#/sender-mobile",
  successParams = {},
  cancelParams = {},
}) {
  const successBase = normalizeSenderAppReturnBase(returnUrl, successPath);
  const successQuery = queryString(successParams);
  return {
    successBase,
    successUrl: successQuery ? `${successBase}${separatorFor(successBase)}${successQuery}` : successBase,
    cancelUrl: senderAppCancelUrl(SENDER_APP_HOME, cancelParams),
  };
}

module.exports = {
  SENDER_APP_ORIGIN,
  SENDER_APP_HOME,
  normalizeOrigin,
  normalizeSenderAppReturnBase,
  senderAppCancelUrl,
  senderAppCheckoutUrls,
};
