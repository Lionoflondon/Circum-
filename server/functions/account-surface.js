/* eslint-disable max-len, require-jsdoc */
const functions = require("firebase-functions/v1");

// Read authority in the same transaction as account creation, before any writes.
async function assertAccountSurface(db, transaction, context, surface) {
  const uid = context.auth.uid;
  const [user, profile, rider, admin] = await Promise.all(
      ["users", "riderProfiles", "riders", "adminUsers"].map((collection) => transaction.get(db.collection(collection).doc(uid))),
  );
  const data = user.data() || {};
  const roles = new Set([...(Array.isArray(data.roles) ? data.roles : []), data.role, data.userType, data.accountType]
      .map((value) => String(value || "").trim().toLowerCase()));
  const sender = ["sender", "user", "customer"].some((role) => roles.has(role));
  const isRider = profile.exists || rider.exists || roles.has("rider");
  const isAdmin = admin.exists || roles.has("admin") || context.auth.token.admin === true;
  const allowed = surface === "sender" ? sender || (!isRider && !isAdmin) : isRider || (!sender && !isAdmin);
  if (!allowed) {
    throw new functions.https.HttpsError("permission-denied", surface === "sender" ?
      "This account belongs to Rider or Admin. Sign in on the correct Circum app." :
      "This account belongs to Sender or Admin. Sign in on the correct Circum app.");
  }
}
module.exports = {assertAccountSurface};
