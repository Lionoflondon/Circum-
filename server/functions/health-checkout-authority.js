/* eslint-disable max-len, require-jsdoc */
const {expireLegacySessions, blocked} = require("./legacy-payment-artifacts");
const VERSION = 2;
const {createHash} = require("node:crypto");
const {healthPlusPricingInputFromBooking} = require("./health-plus-core");
function bookingBinding(booking) {
  return createHash("sha256").update(JSON.stringify({
    senderId: booking.senderId || booking.userId,
    profileId: booking.profileId,
    pharmacyAddress: booking.pharmacyAddress,
    deliveryAddress: booking.deliveryAddress,
    routeAuthorityVersion: booking.routeAuthorityVersion,
    pricing: healthPlusPricingInputFromBooking(booking),
  })).digest("hex");
}
function assertCurrentBooking(snapshot, expected) {
  const current = snapshot.data() || {};
  if (!snapshot.exists || current.routeAuthorityVersion !== VERSION ||
      ["cancelled", "completed", "delivered", "failed", "refunded", "expired", "paid"].includes(String(current.status || "").trim().toLowerCase()) ||
      bookingBinding(current) !== bookingBinding(expected)) {
    throw blocked("Health+ booking changed. Create a fresh booking before paying.", "stale_health_booking");
  }
}

async function legacyGate({stripe, db, bookingId, booking, payment}) {
  if (booking.routeAuthorityVersion === VERSION &&
      (!payment.checkoutSessionId ||
       (payment.pricingAuthorityVersion === VERSION && payment.checkoutAuthority &&
        payment.checkoutAuthority.bookingBinding === bookingBinding(booking)))) return;
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
async function reserve({db, paymentRef, candidate, booking}) {
  return db.runTransaction(async (tx) => {
    const [snap, bookingSnap] = await tx.getAll(paymentRef, db.doc(`prescriptionPickups/${paymentRef.id}`));
    assertCurrentBooking(bookingSnap, booking);
    const current = snap.data() || {};
    if (["paid", "succeeded", "checkout_completed"].includes(current.status)) {
      throw blocked(
        "This Health+ booking has already been paid.",
        "already_paid",
      );
    }
    if (current.checkoutAuthority) {
      if (current.checkoutAuthority.bookingBinding !== bookingBinding(booking)) {
        throw blocked("Health+ checkout requires a fresh booking.", "stale_health_checkout");
      }
      return current.checkoutAuthority;
    }
    const authority = {
      ...candidate,
      bookingBinding: bookingBinding(booking),
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
async function create({db, stripe, paymentRef, params, record, booking}) {
  const frozen = await db.runTransaction(async (tx) => {
    const [snap, bookingSnap] = await tx.getAll(paymentRef, db.doc(`prescriptionPickups/${paymentRef.id}`));
    assertCurrentBooking(bookingSnap, booking);
    const current = snap.data() || {};
    if (["paid", "succeeded", "checkout_completed"].includes(current.status)) {
      throw blocked("This Health+ booking has already been paid.", "already_paid");
    }
    if (!current.checkoutAuthority || current.checkoutAuthority.bookingBinding !== bookingBinding(booking)) {
      throw blocked("Health+ checkout requires a fresh booking.", "stale_health_checkout");
    }
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
module.exports = {VERSION, bookingBinding, assertCurrentBooking, legacyGate, reserve, create};
