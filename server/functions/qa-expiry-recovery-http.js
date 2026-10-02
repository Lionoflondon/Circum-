/* eslint-disable max-len, require-jsdoc */
"use strict";
const {OAuth2Client} = require("google-auth-library");
const {getFirestore} = require("firebase-admin/firestore");
const {getApps, initializeApp} = require("firebase-admin/app");
const {handleRecovery} = require("./legacy-recovery-http");
const AUDIENCE = "https://circum-qa-special-flow-j2b7cicfwq-uc.a.run.app";
const CALLERS = new Set(["circum-payment-scheduler@circum-2797c.iam.gserviceaccount.com", "circum-2797c@appspot.gserviceaccount.com"]);
async function authorize(request, verifier = new OAuth2Client()) {
  const match = /^Bearer ([^\s]+)$/.exec(String(request.headers.authorization || ""));
  if (!match) throw Object.assign(new Error("scheduler_identity_required"), {statusCode: 401});
  let payload;
  try {
payload = (await verifier.verifyIdToken({idToken: match[1], audience: AUDIENCE})).getPayload();
} catch (_) {
    throw Object.assign(new Error("scheduler_identity_required"), {statusCode: 401});
  }
  if (payload.email_verified !== true || !CALLERS.has(payload.email)) throw Object.assign(new Error("scheduler_identity_not_authorized"), {statusCode: 403});
}
function dependencies() {
  if (!getApps().length) initializeApp();
  const secret = process.env.CIRCUM_QA_STRIPE_SECRET_KEY;
  if (!secret?.startsWith("sk_test_")) throw new Error("test_provider_required");
  const credentials = JSON.parse(process.env.CIRCUM_QA_CERTIFICATION_CREDENTIALS || "{}");
  const lists = {operators: [credentials.identities?.admin?.uid], senders: [credentials.identities?.sender?.uid], riders: [credentials.identities?.rider?.uid]};
  const env = {...process.env, STRIPE_MODE: "TEST", QA_LIFECYCLE_ENABLED: "true", QA_LIFECYCLE_ALLOWLIST: JSON.stringify(lists)};
  const stripe = require("stripe")(secret, {timeout: 20000, maxNetworkRetries: 1});
  return {env, stripe, db: getFirestore()};
}
function handleQaRecovery(request, response, options = {}) {
  if (!new URL(request.url, "http://localhost").pathname.startsWith("/recovery/")) return false;
  let cached;
  const load = () => cached || (cached = options.dependencies || dependencies());
  return handleRecovery(request, response, {
    db: () => load().db, workers: ["expireQaLifecycleFixtures", "expireQaSpecialFlowFixtures"], authorize: options.authorize || authorize,
    fixtureRun: async ({db, worker, fixtureId}) => {
      const root = worker === "expireQaSpecialFlowFixtures" ? "qaSpecialFlowFixtures" : "qaLifecycleFixtures";
      const selected = await db.collection(root).doc(fixtureId).get();
      if (!selected.exists || selected.data().id !== fixtureId || selected.data().isSyntheticQa !== true || selected.data().testOnly !== true) throw Object.assign(new Error("fixture_not_authorized"), {statusCode: 403});
      const originalCollection = db.collection.bind(db);
      const scoped = {collection: (name) => name === root ? {doc: (id) => {
if (id !== fixtureId) throw new Error("cross_fixture_access"); return originalCollection(root).doc(id);
}, where: (...args) => originalCollection(root).where(require("firebase-admin/firestore").FieldPath.documentId(), "==", fixtureId).where(...args)} : originalCollection(name), doc: db.doc.bind(db), runTransaction: db.runTransaction.bind(db)};
      const d = load();
      if (worker === "expireQaSpecialFlowFixtures") return require("./qa-special-flow")._test.factory({db: scoped, env: d.env, stripe: d.stripe}).expire();
      const providerFactory = (qa, fixture) => require("./qa-special-provider").paymentProviderForFixture({stripe: d.stripe, qa, fixture, secret: d.env.CIRCUM_QA_STRIPE_SECRET_KEY});
      return require("./qa-lifecycle")._test.factory({db: scoped, env: d.env, providerFactory}).expire();
    },
    run: async ({db, worker}) => {
      const d = load();
      if (worker === "expireQaSpecialFlowFixtures") return require("./qa-special-flow")._test.factory({db, env: d.env, stripe: d.stripe}).expire();
      const providerFactory = (qa, fixture) => require("./qa-special-provider").paymentProviderForFixture({stripe: d.stripe, qa, fixture, secret: d.env.CIRCUM_QA_STRIPE_SECRET_KEY});
      return require("./qa-lifecycle")._test.factory({db, env: d.env, providerFactory}).expire();
    },
  });
}
module.exports = {handleQaRecovery, authorize, CALLERS};
