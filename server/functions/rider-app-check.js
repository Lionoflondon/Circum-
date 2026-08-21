"use strict";

const functions = require("firebase-functions/v1");

function riderCallable(handler) {
  return functions.https.onCall({enforceAppCheck: true}, handler);
}

module.exports = {riderCallable};
