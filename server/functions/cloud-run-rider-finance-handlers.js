/* eslint-disable max-len, require-jsdoc */
"use strict";
const {initializeApp, getApps} = require("firebase-admin/app");
const {resolveStripeRuntimeConfig} = require("./stripe-config");
const rider = require("./rider-connect");
const earnings = require("./rider-earnings-summary");
let stripe;
function stripeClient() {
  if (!stripe) {
    const config = resolveStripeRuntimeConfig();
    stripe = require("stripe")(config.secretKey, {timeout: 20000, maxNetworkRetries: 0});
    stripe._circumStripeMode = config.mode;
  }
  return stripe;
}
function createHandlers(family) {
  if (!getApps().length) initializeApp();
  if (family === "rider_payouts") {
return {
    getRiderEarningsSummary: earnings.getRiderEarningsSummary(),
    riderPayoutReadiness: rider.riderPayoutReadiness(),
    createRiderTransferOrPayout: rider.createRiderTransferOrPayout(stripeClient),
    requestRiderWithdrawal: rider.requestRiderWithdrawal(),
    cancelRiderWithdrawal: rider.cancelRiderWithdrawal(),
    adminReviewRiderWithdrawal: rider.adminReviewRiderWithdrawal(),
    adminReviewRider: require("./admin-rider-authority").adminReviewRider,
    adminReconcileRiderEarnings: earnings.adminReconcileRiderEarnings(),
    adminRecordRiderEvent: require("./admin-operations-authority").adminRecordRiderEvent,
  };
}
  if (family === "rider_connect_accounts") {
return {
    createStripeConnectAccountForRider: rider.createStripeConnectAccountForRider(stripeClient),
    createStripeOnboardingLink: rider.createStripeOnboardingLink(stripeClient),
    refreshStripeOnboardingLink: rider.refreshStripeOnboardingLink(stripeClient),
    syncStripeConnectStatus: rider.syncStripeConnectStatus(stripeClient),
    createStripeAccountManagementLink: rider.createStripeAccountManagementLink(stripeClient),
  };
}
  throw new TypeError("Unsupported Rider finance family");
}
module.exports = {createHandlers};
