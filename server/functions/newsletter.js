/* eslint-disable max-len, require-jsdoc */
"use strict";

const crypto = require("crypto");
const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue, FieldPath} = require("firebase-admin/firestore");
const {adminCallable, requirePermission, requireAppCheck} = require("./admin-permissions");
const adminOperations = require("./admin-operations-authority");

const COLLECTION = "newsletterSubscribers";
const RATE_LIMIT_COLLECTION = "newsletterSignupRateLimits";
const CONSENT_VERSION = "newsletter-consent-v1";
// This is intentionally unset until the amended CIRCUM Privacy Policy has
// been approved and published with a real version/effective date.
const PRIVACY_POLICY_VERSION = process.env.NEWSLETTER_PRIVACY_POLICY_VERSION || null;
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
const RESEND_CONTACTS_URL = "https://api.resend.com/contacts";
const RESEND_TIMEOUT_MS = 15 * 1000;

function clean(value, max = 240) {
  return `${value || ""}`.trim().slice(0, max);
}

function normalizeEmail(value) {
  if (typeof value !== "string" || value.trim().length > 254) {
    throw new functions.https.HttpsError("invalid-argument", "Enter a valid email address.");
  }
  const email = value.trim().toLowerCase();
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
  if (!categories.length) {
    throw new functions.https.HttpsError("invalid-argument", "Choose an interest or unsubscribe from all marketing.");
  }
  return categories.sort();
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

function resendNewsletterProvider({apiKey = process.env.RESEND_NEWSLETTER_API_KEY, fetchImpl = global.fetch} = {}) {
  if (!apiKey || typeof fetchImpl !== "function") return providerBoundary();

  async function request(method, url, body) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), RESEND_TIMEOUT_MS);
    try {
      const response = await fetchImpl(url, {
        method,
        headers: {Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json"},
        body: JSON.stringify(body),
        signal: controller.signal,
      });
      return response;
    } catch (_) {
      throw new Error("resend_request_failed");
    } finally {
      clearTimeout(timeout);
    }
  }

  async function requireSuccess(response) {
    if (!response || !response.ok) {
      throw new Error(`resend_http_${response && response.status || "unknown"}`);
    }
    return {status: "synced"};
  }

  return {
    async upsertAudienceMember({email, status}) {
      const unsubscribed = status !== "active";
      const contactUrl = `${RESEND_CONTACTS_URL}/${encodeURIComponent(email)}`;
      const body = {email, unsubscribed};
      const update = await request("PATCH", contactUrl, body);
      if (update.status === 404) {
        return requireSuccess(await request("POST", RESEND_CONTACTS_URL, body));
      }
      if (update.status === 409 || update.status === 422) {
        return requireSuccess(await request("POST", RESEND_CONTACTS_URL, body));
      }
      return requireSuccess(update);
    },
  };
}

function createService({db = getFirestore(), provider = resendNewsletterProvider(), now = () => Date.now(), tokenFactory = randomToken} = {}) {
  async function syncProvider(ref, payload, revision) {
    // Adapters must apply revision monotonically and recheck local suppression
    // before any send. Audience synchronization is never proof of delivery.
    let status = "retry_required";
    try {
      const result = await provider.upsertAudienceMember({...payload, revision});
      status = result && ["synced", "pending_configuration"].includes(result.status) ? result.status : "retry_required";
    } catch (_) {/* Retain explicit retry work; there is no automatic retry loop. */}
    await db.runTransaction(async (tx) => {
      const current = await tx.get(ref);
      if (!current.exists || current.data().revision !== revision) return;
      tx.set(ref, {providerSyncStatus: status, providerLastAttemptAt: FieldValue.serverTimestamp()}, {merge: true});
    });
  }

  async function signup(data) {
    assertNoBotPayload(data);
    if (data.consent !== true) {
      throw new functions.https.HttpsError("invalid-argument", "Newsletter consent is required.");
    }
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
    let revision = 0;

    await db.runTransaction(async (tx) => {
      // Firestore may rerun this callback after a conflicting transaction.
      shouldSyncProvider = false;
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
        expiresAt: new Date(startedAt + 24 * 60 * 60 * 1000),
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});

      const existing = subscriberSnapshot.exists ? subscriberSnapshot.data() : null;
      if (existing && existing.status === "active") {
        outcome = "already_active";
        // Knowing an email address is not authority to edit its preferences.
        return;
      }

      outcome = existing ? "resubscribed" : "created";
      shouldSyncProvider = true;
      revision = Number(existing && existing.revision || 0) + 1;
      tx.set(subscriber, {
        email,
        emailHash: id,
        status: "active",
        revision,
        categories,
        source,
        signupSource: source,
        lastSignupSource: source,
        consentAt: FieldValue.serverTimestamp(),
        consentWording: "By joining, you agree to receive CIRCUM marketing emails. Unsubscribe anytime.",
        consentVersion: CONSENT_VERSION,
        privacyPolicyVersion: PRIVACY_POLICY_VERSION,
        privacyPolicyVersionStatus: PRIVACY_POLICY_VERSION ? "configured" : "approval_required",
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
        privacyPolicyVersionStatus: PRIVACY_POLICY_VERSION ? "configured" : "approval_required",
        createdAt: FieldValue.serverTimestamp(),
      });
    });

    if (shouldSyncProvider) {
      await syncProvider(subscriber, {email, categories, status: "active", unsubscribeToken: token}, revision);
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
    const change = await db.runTransaction(async (tx) => {
      const current = await tx.get(doc.ref);
      const record = current.exists ? current.data() : null;
      if (!record || record.unsubscribeTokenHash !== sha256(token)) {
        throw new functions.https.HttpsError("permission-denied", "This unsubscribe link is invalid.");
      }
      if (record.status !== "unsubscribed") {
        const revision = Number(record.revision || 0) + 1;
        tx.set(doc.ref, {revision, status: "unsubscribed", categories: [], unsubscribedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(), providerSyncStatus: "pending"}, {merge: true});
        tx.set(doc.ref.collection("consentEvents").doc(), {type: "unsubscribed", createdAt: FieldValue.serverTimestamp()});
        tx.set(db.collection("newsletterAnalyticsEvents").doc(), {event: "newsletter_unsubscribed", source: record.signupSource, createdAt: FieldValue.serverTimestamp()});
        return {email: record.email, revision};
      }
      return record.providerSyncStatus === "retry_required" ? {email: record.email, revision: record.revision} : null;
    });
    if (change) {
      await syncProvider(doc.ref, {email: change.email, categories: [], status: "unsubscribed"}, change.revision);
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
    const change = await db.runTransaction(async (tx) => {
      const current = await tx.get(ref);
      const record = current.exists ? current.data() : null;
      if (!record || record.status !== "active" || record.unsubscribeTokenHash !== sha256(token)) {
        throw new functions.https.HttpsError("permission-denied", "This preferences link is invalid.");
      }
      const revision = Number(record.revision || 0) + 1;
      tx.set(ref, {revision, categories, updatedAt: FieldValue.serverTimestamp(), providerSyncStatus: "pending"}, {merge: true});
      tx.set(ref.collection("consentEvents").doc(), {type: "preferences_updated", categories, createdAt: FieldValue.serverTimestamp()});
      tx.set(db.collection("newsletterAnalyticsEvents").doc(), {event: "newsletter_preferences_updated", source: record.signupSource, createdAt: FieldValue.serverTimestamp()});
      return {email: record.email, revision};
    });
    await syncProvider(ref, {email: change.email, categories, status: "active"}, change.revision);
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

async function limitPublicRequest(db, context, method, now = Date.now()) {
  const ip = context.rawRequest && context.rawRequest.ip;
  if (!ip) throw new functions.https.HttpsError("failed-precondition", "Request origin is unavailable.");
  const bucket = Math.floor(now / RATE_WINDOW_MS);
  // A global budget also bounds traffic that rotates both IP and email.
  const refs = [
    db.collection(RATE_LIMIT_COLLECTION).doc(`global-${method}`),
    db.collection(RATE_LIMIT_COLLECTION).doc(`origin-${sha256(`${bucket}:${ip}`)}`),
  ];
  await db.runTransaction(async (tx) => {
    const snapshots = await Promise.all(refs.map((ref) => tx.get(ref)));
    const counts = snapshots.map((snapshot) => {
      const record = snapshot.exists ? snapshot.data() : {};
      return record.bucket === bucket ? Number(record.attempts || 0) : 0;
    });
    if (counts[0] >= 1000 || counts[1] >= 60) {
      throw new functions.https.HttpsError("resource-exhausted", "Please wait before trying again.");
    }
    refs.forEach((ref, index) => tx.set(ref, {
      bucket, attempts: counts[index] + 1,
      expiresAt: new Date(now + 24 * 60 * 60 * 1000),
      updatedAt: FieldValue.serverTimestamp(),
    }));
  });
}

function publicCallable(method) {
  return functions.runWith({enforceAppCheck: true, maxInstances: 3, timeoutSeconds: 30}).https.onCall(async (data, context) => {
    requireAppCheck(context);
    if (["signup", "recordEvent"].includes(method) &&
        (process.env.NEWSLETTER_SIGNUP_ENABLED !== "true" || !PRIVACY_POLICY_VERSION)) {
      throw new functions.https.HttpsError("failed-precondition", "Newsletter signup is not available yet.");
    }
    assertNoBotPayload(data);
    await limitPublicRequest(getFirestore(), context, method);
    const result = await createService()[method](data);
    // Public signup must not disclose whether an address was already present.
    return method === "signup" ? {ok: true} : result;
  });
}

exports.submitNewsletterSignup = publicCallable("signup");
exports.getNewsletterPreferences = publicCallable("preferences");
exports.updateNewsletterPreferences = publicCallable("updatePreferences");
exports.unsubscribeNewsletter = publicCallable("unsubscribe");
exports.recordNewsletterAnalytics = publicCallable("recordEvent");

async function newsletterActor(context, permission) {
  const actor = await adminOperations._private.resolveActor(context);
  requirePermission(actor, permission, "Newsletter Audience access is required.");
  return actor;
}

exports.adminNewsletterDashboard = adminCallable(async (_data, context) => {
  await newsletterActor(context, "newsletter.read");
  const db = getFirestore();
  const since = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
  const previousSince = new Date(since.getTime() - 30 * 24 * 60 * 60 * 1000);
  const [active, unsubscribed, recent, previous] = await Promise.all([
    db.collection(COLLECTION).where("status", "==", "active").count().get(),
    db.collection(COLLECTION).where("status", "==", "unsubscribed").count().get(),
    db.collection(COLLECTION).where("createdAt", ">=", since).count().get(),
    db.collection(COLLECTION).where("createdAt", ">=", previousSince).where("createdAt", "<", since).count().get(),
  ]);
  const countBy = async (values, field, operator) => Object.fromEntries(await Promise.all(values.map(async (value) => {
    const result = await db.collection(COLLECTION).where(field, operator, value).count().get();
    return [value, result.data().count];
  })));
  const [sources, categories] = await Promise.all([
    countBy([...SOURCES], "signupSource", "=="), countBy(CATEGORIES, "categories", "array-contains"),
  ]);
  return {ok: true, active: active.data().count, unsubscribed: unsubscribed.data().count,
    newLast30Days: recent.data().count, newPrevious30Days: previous.data().count,
    growth: recent.data().count - previous.data().count, sources, categories};
});

function audienceRecord(doc) {
  const record = doc.data();
  return {id: doc.id, email: record.email, status: record.status,
    categories: record.categories || [], signupSource: record.signupSource,
    subscribedAt: timestampMillis(record.subscribedAt),
    providerSyncStatus: record.providerSyncStatus};
}

exports.adminSearchNewsletterSubscribers = adminCallable(async (data, context) => {
  await newsletterActor(context, "newsletter.read");
  const query = clean(data && data.query, 254).toLowerCase();
  const emailHash = query.includes("@") ? sha256(normalizeEmail(query)) : clean(data && data.emailHash, 64);
  if (!/^[a-f0-9]{64}$/.test(emailHash)) throw new functions.https.HttpsError("invalid-argument", "Search by email or email hash.");
  const doc = await getFirestore().collection(COLLECTION).doc(emailHash).get();
  return {ok: true, records: doc.exists ? [audienceRecord(doc)] : []};
});

exports.adminExportNewsletterSubscribers = adminCallable(async (data, context) => {
  await newsletterActor(context, "newsletter.export");
  let query = getFirestore().collection(COLLECTION).where("status", "==", "active").orderBy(FieldPath.documentId());
  if (data && data.cursor) {
    if (typeof data.cursor !== "string" || !/^[a-f0-9]{64}$/.test(data.cursor)) {
      throw new functions.https.HttpsError("invalid-argument", "Invalid audience cursor.");
    }
    query = query.startAfter(data.cursor);
  }
  const snapshot = await query.limit(501).get();
  const docs = snapshot.docs.slice(0, 500);
  return {ok: true, records: docs.map(audienceRecord),
    nextCursor: snapshot.docs.length > 500 ? docs.at(-1).id : null};
});

exports._private = {normalizeEmail, sha256, normalizeCategories, createService, limitPublicRequest, resendNewsletterProvider, CATEGORIES, DEFAULT_CATEGORIES, PRIVACY_POLICY_VERSION};
