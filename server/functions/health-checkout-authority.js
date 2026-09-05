/* eslint-disable max-len, require-jsdoc */
const {expireLegacySessions, blocked} = require("./legacy-payment-artifacts");
const VERSION = 2;
async function legacyGate({stripe, db, bookingId, booking, payment}) {
  if (booking.routeAuthorityVersion === VERSION) return;
  try {
    await expireLegacySessions({
      stripe,
      knownIds: [payment.checkoutSessionId],
      matches: (s) =>
        s.metadata &&
        s.metadata.bookingId === bookingId &&
        s.metadata.type === "health_plus_payment",
    });
  } catch (error) {
    await db.doc(`paymentArtifactReconciliations/health_${bookingId}`).set(
      {
        service: "health_plus",
        bookingId,
        status: "review_required",
        reason:
          (error.details && error.details.reason) ||
          "provider_state_unconfirmed",
        updatedAt: Date.now(),
      },
      {merge: true},
    );
    throw error;
  }
  await db.doc(`prescriptionPickups/${bookingId}`).set(
    {
      paymentRegenerationRequired: true,
      paymentStatus: "regeneration_required",
      updatedAt: Date.now(),
    },
    {merge: true},
  );
  throw blocked(
    "This Health+ booking needs a fresh route price. Create a new booking before paying.",
    "health_booking_regeneration_required",
  );
}
async function reserve({db, paymentRef, candidate}) {
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(paymentRef);
    const current = snap.data() || {};
    if (["paid", "succeeded", "checkout_completed"].includes(current.status)) {
      throw blocked(
        "This Health+ booking has already been paid.",
        "already_paid",
      );
    }
    if (current.checkoutAuthority) return current.checkoutAuthority;
    const authority = {
      ...candidate,
      version: VERSION,
      expiresAt: Math.floor(Date.now() / 1000) + 1860,
    };
    tx.set(
      paymentRef,
      {checkoutAuthority: authority, pricingAuthorityVersion: VERSION},
      {merge: true},
    );
    return authority;
  });
}
async function create({db, stripe, paymentRef, params, record}) {
  const frozen = await db.runTransaction(async (tx) => {
    const snap = await tx.get(paymentRef);
    const current = snap.data() || {};
    if (current.providerParams) return current.providerParams;
    tx.set(
      paymentRef,
      {
        ...record,
        pricingAuthorityVersion: VERSION,
        providerParams: JSON.parse(JSON.stringify(params)),
      },
      {merge: true},
    );
    return JSON.parse(JSON.stringify(params));
  });
  const session = await stripe.checkout.sessions.create(frozen, {
    idempotencyKey: `health_checkout_v${VERSION}_${paymentRef.id}`,
  });
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(paymentRef);
    const current = snap.data() || {};
    tx.set(
      paymentRef,
      {
        checkoutSessionId: session.id,
        checkoutUrl: session.url,
        ...(!["paid", "succeeded"].includes(current.status) ?
          {status: "pending_verification"} :
          {}),
      },
      {merge: true},
    );
  });
  return session;
}
module.exports = {VERSION, legacyGate, reserve, create};
