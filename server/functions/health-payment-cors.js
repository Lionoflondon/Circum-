"use strict";

// Header permission is separate from authentication and App Check verification.
module.exports = function allowHealthPaymentCors(res) {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Firebase-AppCheck");
  res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
};
