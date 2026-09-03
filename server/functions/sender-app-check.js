"use strict";

const functions = require("firebase-functions/v1");

function senderPaymentCallable(handler, options = {}) {
  return functions
      .runWith({...options, enforceAppCheck: true})
      .https.onCall(handler);
}

module.exports = {senderPaymentCallable};
