"use strict";

const functions = require("firebase-functions/v1");

function riderCallable(handler) {
  return functions.runWith({enforceAppCheck: true}).https.onCall(handler);
}

module.exports = {riderCallable};
