/* eslint-disable max-len, require-jsdoc */
"use strict";

const crypto = require("crypto");
const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {adminCallable, requirePermission} = require("./admin-permissions");
const adminOperations = require("./admin-operations-authority");

const COLLECTION = "newsletterSubscribers";
const RATE_LIMIT_COLLECTION = "newsletterSignupRateLimits";
const CONSENT_VERSION = "newsletter-consent-v1";
// This is intentionally unset until the amended CIRCUM Privacy Policy has
// been approved and published with a real version/effective date.
const PRIVACY_POLICY_VERSION = null;
const DEFAULT_CATEGORIES = Object.freeze(["circum_updates"]);
const CATEGORIES = Object.freeze([
  "circum_updates", "offers_rewards", "rider_opportunities", "business_partnerships",
]);
const SOURCES = new Set(["homepage", "footer", "rider_page", "business_page", "campaign"]);
const EVENTS = new Set([
  "newsletter_signup_viewed", "newsletter_signup_started", "newsletter_signup_completed",
  "newsletter_signup_failed", "newsletter_preferences_updated", "newsletter_unsubscribed",
]);
const RATE_WINDOW_MS = 15 * 60 * 1000;
const RATE_MAX = 5;

function clean(value, max = 240) {
  return `${value || ""}`.trim().slice(0, max);
}

function normalizeEmail(value) {
  const email = clean(value, 254).toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/u.test(email)) {
    throw new functions.https.HttpsError("invalid-argument", "Enter a valid email address.");
  }
  return email;
}

function sha256(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}

function randomToken() {
  return crypto.randomBytes(32).toString("base64url");
}

function validSource(value) {
  const source = clean(value, 64).toLowerCase();
  if (!SOURCES.has(source)) {
    throw new functions.https.HttpsError("invalid-argument", "Unsupported signup source.");
  }
  return source;
}

function normalizeCategories(value) {
  if (value == null) return [...DEFAULT_CATEGORIES];
  if (!Array.isArray(value) || value.length > CATEGORIES.length) {
    throw new functions.https.HttpsError("invalid-argument", "Invalid newsletter preferences.");
  }
  const categories = [...new Set(value.map((item) => clean(item, 64).toLowerCase()))];
  if (categories.some((item) => !CATEGORIES.includes(item))) {
    throw new functions.https.HttpsError("invalid-argument", "Invalid newsletter preference.");
  }
  return categories.length ? categories : [...DEFAULT_CATEGORIES];
}

function timestampMillis(value) {
  if (!value) return 0;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  return Number(value) || 0;
}

function safeEvent(value) {
  const event = clean(value, 80);
  if (!EVENTS.has(event)) {
    throw new functions.https.HttpsError("invalid-argument", "Unsupported newsletter event.");
  }
  return event;
}

function assertNoBotPayload(data) {
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    throw new functions.https.HttpsError("invalid-argument", "Malformed newsletter request.");
  }
  if (clean(data.website, 8)) {
    throw new functions.https.HttpsError("permission-denied", "Unable to process this signup.");
  }
}

function providerBoundary() {
  return {
    async upsertAudienceMember() {
      // Deliberately no-op until a provider adapter is configured. A provider
      // outage must never prevent consent/suppression from being persisted.
      return {status: "pending_configuration"};
    },
  };
}

function createService({db = getFirestore(), provider = providerBoundary(), now = () => Date.now(), tokenFactory = randomToken} = {}) {
  async function signup(data) {
    assertNoBotPayload(data);
    const email = normalizeEmail(data.email);
    const source = validSource(data.source);
    const categories = normalizeCategories(data.categories);
    const id = sha256(email);
    const subscriber = db.collection(COLLECTION).doc(id);
    const rateLimit = db.collection(RATE_LIMIT_COLLECTION).doc(id);
    const token = tokenFactory();
    const tokenHash = sha256(token);
    const startedAt = now();
    let outcome = "created";
    let shouldSyncProvider = false;

    await db.runTransaction(async (tx) => {
      const [subscriberSnapshot, limitSnapshot] = await Promise.all([
        tx.get(subscriber), tx.get(rateLimit),
      ]);
      const previousLimit = limitSnapshot.exists ? limitSnapshot.data() : {};
      const windowStartedAt = timestampMillis(previousLimit.windowStartedAt);
      const inWindow = windowStartedAt > 0 && startedAt - windowStartedAt < RATE_WINDOW_MS;
      const attempts = inWindow ? Number(previousLimit.attempts || 0) : 0;
      if (attempts >= RATE_MAX) {
        throw new functions.https.HttpsError("resource-exhausted", "Please wait before trying again.");
      }
      tx.set(rateLimit, {
        attempts: attempts + 1,
        windowStartedAt: inWindow ? previousLimit.windowStartedAt : new Date(startedAt),
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});

      const existing = subscriberSnapshot.exists ? subscriberSnapshot.data() : null;
      if (existing && existing.status === "active") {
        outcome = "already_active";
        const sameCategories = JSON.stringify(existing.categories || []) === JSON.stringify(categories);
        if (!sameCategories) {
          tx.set(subscriber, {
            categories,
            updatedAt: FieldValue.serverTimestamp(),
            lastSignupSource: source,
          }, {merge: true});
          tx.set(subscriber.collection("consentEvents").doc(), {
            type: "preferences_updated", categories, source,
            consentVersion: CONSENT_VERSION,
            privacyPolicyVersion: PRIVACY_POLICY_VERSION,
            createdAt: FieldValue.serverTimestamp(),
          });
          outcome = "preferences_updated";
          shouldSyncProvider = true;
        }
        return;
      }

      outcome = existing ? "resubscribed" : "created";
      shouldSyncProvider = true;
      tx.set(subscriber, {
        email,
        emailHash: id,
        status: "active",
        categories,
        source,
        signupSource: source,
        lastSignupSource: source,
        consentAt: FieldValue.serverTimestamp(),
        consentWording: "I want to receive CIRCUM marketing emails. I can unsubscribe at any time.",
        consentVersion: CONSENT_VERSION,
        privacyPolicyVersion: PRIVACY_POLICY_VERSION,
        privacyPolicyVersionStatus: "approval_required",
        verificationState: "not_required",
        unsubscribeTokenHash: tokenHash,
        createdAt: existing ? existing.createdAt || FieldValue.serverTimestamp() : FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        subscribedAt: FieldValue.serverTimestamp(),
        unsubscribedAt: null,
        providerSyncStatus: "pending",
      }, {merge: true});
      tx.set(subscriber.collection("consentEvents").doc(), {
        type: existing ? "resubscribed" : "subscribed", categories, source,
        consentVersion: CONSENT_VERSION,
        privacyPolicyVersion: PRIVACY_POLICY_VERSION,
        privacyPolicyVersionStatus: "approval_required",
        createdAt: FieldValue.serverTimestamp(),
      });
    });

    if (shouldSyncProvider) {
      try {
        const result = await provider.upsertAudienceMember({email, categories, status: "active", unsubscribeToken: token});
        await subscriber.set({providerSyncStatus: result.status || "synced", providerLastSyncedAt: FieldValue.serverTimestamp()}, {merge: true});
      } catch (_) {
        await subscriber.set({providerSyncStatus: "retry_required", providerLastErrorAt: FieldValue.serverTimestamp()}, {merge: true});
      }
    }
    return {ok: true, outcome};
  }

  async function preferences(data) {
    assertNoBotPayload(data);
    const token = clean(data.token, 200);
    if (token.length < 32) throw new functions.https.HttpsError("permission-denied", "This unsubscribe link is invalid.");
    const snapshot = await db.collection(COLLECTION).where("unsubscribeTokenHash", "==", sha256(token)).limit(1).get();
    if (snapshot.empty) throw new functions.https.HttpsError("permission-denied", "This unsubscribe link is invalid.");
    const doc = snapshot.docs[0];
    const record = doc.data();
    return {ok: true, status: record.status, categories: record.categories || DEFAULT_CATEGORIES};
  }

  async function unsubscribe(data) {
    assertNoBotPayload(data);
    const token = clean(data.token, 200);
    if (token.length < 32) throw new functions.https.HttpsError("permission-denied", "This unsubscribe link is invalid.");
    const snapshot = await db.collection(COLLECTION).where("unsubscribeTokenHash", "==", sha256(token)).limit(1).get();
    if (snapshot.empty) throw new functions.https.HttpsError("permission-denied", "This unsubscribe link is invalid.");
    const doc = snapshot.docs[0];
    const record = doc.data();
    if (record.status !== "unsubscribed") {
      await db.runTransaction(async (tx) => {
        tx.set(doc.ref, {status: "unsubscribed", categories: [], unsubscribedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(), providerSyncStatus: "pending"}, {merge: true});
        tx.set(doc.ref.collection("consentEvents").doc(), {type: "unsubscribed", createdAt: FieldValue.serverTimestamp()});
      });
      try {
        const result = await provider.upsertAudienceMember({
          email: record.email, categories: [], status: "unsubscribed",
        });
        await doc.ref.set({providerSyncStatus: result.status || "synced", providerLastSyncedAt: FieldValue.serverTimestamp()}, {merge: true});
      } catch (_) {
        await doc.ref.set({providerSyncStatus: "retry_required", providerLastErrorAt: FieldValue.serverTimestamp()}, {merge: true});
      }
    }
    return {ok: true, status: "unsubscribed"};
  }

  async function updatePreferences(data) {
    assertNoBotPayload(data);
    const token = clean(data.token, 200);
    const categories = normalizeCategories(data.categories);
    const snapshot = await db.collection(COLLECTION).where("unsubscribeTokenHash", "==", sha256(token)).limit(1).get();
    if (snapshot.empty || snapshot.docs[0].data().status !== "active") throw new functions.https.HttpsError("permission-denied", "This preferences link is invalid.");
    const doc = snapshot.docs[0];
    const ref = doc.ref;
    await db.runTransaction(async (tx) => {
      tx.set(ref, {categories, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
      tx.set(ref.collection("consentEvents").doc(), {type: "preferences_updated", categories, createdAt: FieldValue.serverTimestamp()});
    });
    try {
      const result = await provider.upsertAudienceMember({email: doc.data().email, categories, status: "active"});
      await ref.set({providerSyncStatus: result.status || "synced", providerLastSyncedAt: FieldValue.serverTimestamp()}, {merge: true});
    } catch (_) {
      await ref.set({providerSyncStatus: "retry_required", providerLastErrorAt: FieldValue.serverTimestamp()}, {merge: true});
    }
    return {ok: true, categories};
  }

  async function recordEvent(data) {
    assertNoBotPayload(data);
    const event = safeEvent(data.event);
    const source = validSource(data.source);
    await db.collection("newsletterAnalyticsEvents").add({event, source, createdAt: FieldValue.serverTimestamp()});
    return {ok: true};
  }

  return {signup, preferences, unsubscribe, updatePreferences, recordEvent};
}

exports.submitNewsletterSignup = functions.runWith({enforceAppCheck: true}).https.onCall((data, context) => createService().signup(data, context));
exports.getNewsletterPreferences = functions.runWith({enforceAppCheck: true}).https.onCall((data) => createService().preferences(data));
exports.updateNewsletterPreferences = functions.runWith({enforceAppCheck: true}).https.onCall((data) => createService().updatePreferences(data));
exports.unsubscribeNewsletter = functions.runWith({enforceAppCheck: true}).https.onCall((data) => createService().unsubscribe(data));
exports.recordNewsletterAnalytics = functions.runWith({enforceAppCheck: true}).https.onCall((data) => createService().recordEvent(data));

async function newsletterActor(context, permission) {
  const actor = await adminOperations._private.resolveActor(context);
  requirePermission(actor, permission, "Newsletter Audience access is required.");
  return actor;
}

exports.adminNewsletterDashboard = adminCallable(async (_data, context) => {
  await newsletterActor(context, "newsletter.read");
  const db = getFirestore();
  const [active, unsubscribed, recent] = await Promise.all([
    db.collection(COLLECTION).where("status", "==", "active").count().get(),
    db.collection(COLLECTION).where("status", "==", "unsubscribed").count().get(),
    db.collection(COLLECTION).where("subscribedAt", ">=", new Date(Date.now() - 30 * 24 * 60 * 60 * 1000)).count().get(),
  ]);
  return {ok: true, active: active.data().count, unsubscribed: unsubscribed.data().count, newLast30Days: recent.data().count};
});

exports.adminSearchNewsletterSubscribers = adminCallable(async (data, context) => {
  await newsletterActor(context, "newsletter.read");
  const query = clean(data && data.query, 254).toLowerCase();
  const emailHash = query.includes("@") ? sha256(normalizeEmail(query)) : clean(data && data.emailHash, 64);
  if (!emailHash) throw new functions.https.HttpsError("invalid-argument", "Search by email or email hash.");
  const doc = await getFirestore().collection(COLLECTION).doc(emailHash).get();
  return {ok: true, records: doc.exists ? [{id: doc.id, ...doc.data()}] : []};
});

exports.adminExportNewsletterSubscribers = adminCallable(async (_data, context) => {
  await newsletterActor(context, "newsletter.export");
  const snapshot = await getFirestore().collection(COLLECTION).where("status", "==", "active").limit(1000).get();
  return {ok: true, records: snapshot.docs.map((doc) => ({id: doc.id, ...doc.data()}))};
});

exports._private = {normalizeEmail, sha256, normalizeCategories, createService, CATEGORIES, DEFAULT_CATEGORIES, PRIVACY_POLICY_VERSION};
