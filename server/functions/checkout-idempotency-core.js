/* eslint-disable require-jsdoc */
"use strict";

const crypto = require("crypto");

class CheckoutClaimError extends Error {
  constructor(reason, message) {
    super(message);
    this.name = "CheckoutClaimError";
    this.reason = reason;
  }
}

function canonicalValue(value) {
  if (Array.isArray(value)) return value.map(canonicalValue);
  if (value && typeof value === "object") {
    return Object.fromEntries(
        Object.keys(value)
            .sort()
            .map((key) => [key, canonicalValue(value[key])]),
    );
  }
  return value === undefined ? null : value;
}

function checkoutFingerprint(value) {
  return crypto
      .createHash("sha256")
      .update(JSON.stringify(canonicalValue(value)))
      .digest("hex");
}

function checkoutLogicalKey(flow, identity) {
  const safeFlow = `${flow || "checkout"}`
      .trim()
      .toLowerCase()
      .replace(/[^a-z0-9_]+/g, "_")
      .replace(/^_+|_+$/g, "")
      .slice(0, 40) || "checkout";
  return `${safeFlow}_${checkoutFingerprint(identity).slice(0, 40)}`;
}

function stripeCheckoutIdempotencyKey(logicalKey) {
  return `circum_checkout_${checkoutFingerprint(logicalKey)}`;
}

function checkoutClaim(existing = {}, {
  logicalKey,
  requestFingerprint,
  returnOwner,
  sessionIdFields = ["checkoutSessionId", "stripeCheckoutSessionId", "stripeSessionId"],
  checkoutUrlFields = ["checkoutUrl", "url"],
  paidStatuses = ["paid", "succeeded", "checkout_completed"],
} = {}) {
  const normalizedOwner = `${returnOwner || ""}`.trim();
  const normalizedLogicalKey = `${logicalKey || ""}`.trim();
  const normalizedFingerprint = `${requestFingerprint || ""}`.trim();
  if (!normalizedOwner || !normalizedLogicalKey || !normalizedFingerprint) {
    throw new CheckoutClaimError("invalid_claim", "Checkout ownership could not be established.");
  }

  const statuses = [existing.paymentStatus, existing.status]
      .map((value) => `${value || ""}`.trim().toLowerCase())
      .filter(Boolean);
  if (statuses.some((status) => paidStatuses.includes(status))) {
    throw new CheckoutClaimError("already_paid", "This checkout has already been paid.");
  }

  const sessionId = sessionIdFields
      .map((field) => `${existing[field] || ""}`.trim())
      .find(Boolean) || "";
  const checkoutUrl = checkoutUrlFields
      .map((field) => `${existing[field] || ""}`.trim())
      .find(Boolean) || "";
  const storedOwner = `${existing.returnOwner || ""}`.trim();
  const storedLogicalKey = `${existing.checkoutLogicalKey || ""}`.trim();
  const storedFingerprint = `${existing.checkoutRequestFingerprint || ""}`.trim();
  const hasClaim = Boolean(storedOwner || storedLogicalKey || storedFingerprint);

  if (hasClaim && storedOwner !== normalizedOwner) {
    throw new CheckoutClaimError(
        "owner_mismatch",
        "This checkout belongs to another Circum product. Resume it from the product where it was started.",
    );
  }
  if (hasClaim && storedLogicalKey !== normalizedLogicalKey) {
    throw new CheckoutClaimError(
        "logical_mismatch",
        "The existing checkout no longer matches this payment request.",
    );
  }
  if (hasClaim && storedFingerprint !== normalizedFingerprint) {
    throw new CheckoutClaimError(
        "request_mismatch",
        "The existing checkout uses different payment details. Complete or expire it before starting another.",
    );
  }

  if (sessionId) {
    if (!hasClaim || !checkoutUrl) {
      throw new CheckoutClaimError(
          "incomplete_session",
          "An existing checkout could not be safely resumed. Contact Circum support before retrying payment.",
      );
    }
    return {
      kind: "reuse",
      sessionId,
      checkoutUrl,
      claim: {
        checkoutLogicalKey: normalizedLogicalKey,
        checkoutRequestFingerprint: normalizedFingerprint,
        returnOwner: normalizedOwner,
      },
    };
  }

  return {
    kind: "claim",
    sessionId: "",
    checkoutUrl: "",
    claim: {
      checkoutLogicalKey: normalizedLogicalKey,
      checkoutRequestFingerprint: normalizedFingerprint,
      returnOwner: normalizedOwner,
    },
  };
}

async function createStripeCheckoutOnce({stripe, logicalKey, params}) {
  return stripe.checkout.sessions.create(params, {
    idempotencyKey: stripeCheckoutIdempotencyKey(logicalKey),
  });
}

module.exports = {
  CheckoutClaimError,
  checkoutClaim,
  checkoutFingerprint,
  checkoutLogicalKey,
  createStripeCheckoutOnce,
  stripeCheckoutIdempotencyKey,
};
