/* eslint-disable require-jsdoc */
"use strict";

const functions = require("firebase-functions/v1");

function requireAppCheck(context) {
  if (!context || !context.app) {
    throw new functions.https.HttpsError(
        "failed-precondition",
        "Circum security verification is required. Please retry.",
    );
  }
}

module.exports = {
  requireAppCheck,
};
