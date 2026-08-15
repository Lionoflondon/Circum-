/* eslint-disable require-jsdoc */
"use strict";

const APP_ORIGIN = "https://circum-app-2797c.web.app";
const LEGACY_APP_ORIGIN = "https://circum-2797c.web.app";

const DEFAULTS = {
  senderDelivery: `${APP_ORIGIN}/#/sender-mobile/send`,
  senderWallet: `${APP_ORIGIN}/#/sender-mobile/wallet`,
  business: `${APP_ORIGIN}/#/sender-mobile/business`,
  gifts: `${APP_ORIGIN}/#/sender-mobile/gifts/payment`,
  healthPlus: `${APP_ORIGIN}/#/sender-mobile/health`,
};

const REQUIRED_HASH = {
  senderDelivery: "#/sender-mobile/send",
  senderWallet: "#/sender-mobile/wallet",
  business: "#/sender-mobile/business",
  gifts: "#/sender-mobile/gifts",
  healthPlus: "#/sender-mobile/health",
};

function normalizeAppOrigin(url) {
  if (url.origin === LEGACY_APP_ORIGIN) {
    url.protocol = "https:";
    url.host = "circum-app-2797c.web.app";
  }
  return url;
}

function paymentReturnBase(product, requested) {
  const fallback = DEFAULTS[product] || DEFAULTS.senderDelivery;
  const requiredHash = REQUIRED_HASH[product];
  try {
    const url = normalizeAppOrigin(new URL(`${requested || fallback}`));
    if (url.origin !== APP_ORIGIN) return fallback;
    if (requiredHash && !url.hash.startsWith(requiredHash)) return fallback;
    url.search = "";
    if (url.hash.includes("?")) {
      url.hash = url.hash.slice(0, url.hash.indexOf("?"));
    }
    return url.toString();
  } catch (error) {
    return fallback;
  }
}

function appendCheckoutParams(baseUrl, params) {
  const url = new URL(paymentReturnBase("senderDelivery", baseUrl));
  Object.entries(params || {}).forEach(([key, value]) => {
    if (value !== undefined && value !== null && `${value}`.length) {
      url.searchParams.set(key, `${value}`);
    }
  });
  return url.toString();
}

function appendParams(baseUrl, params) {
  const url = new URL(baseUrl);
  Object.entries(params || {}).forEach(([key, value]) => {
    if (value !== undefined && value !== null && `${value}`.length) {
      url.searchParams.set(key, `${value}`);
    }
  });
  return url.toString();
}

module.exports = {
  APP_ORIGIN,
  DEFAULTS,
  appendCheckoutParams,
  appendParams,
  paymentReturnBase,
};
