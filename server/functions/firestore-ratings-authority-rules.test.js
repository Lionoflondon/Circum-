/* eslint-disable max-len, require-jsdoc */
const {test, before, after} = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {initializeTestEnvironment, assertFails, assertSucceeds} = require("@firebase/rules-unit-testing");
const {doc, getDoc, setDoc, updateDoc} = require("firebase/firestore");
const ratings = require("./ratings-tipping");
let app; let db; let env;
const context = (uid) => ({auth: {uid, token: {}}});
before(async () => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, "Emulator required");
  const projectId = "demo-ratings-authority";
  app = initializeApp({projectId}); db = getFirestore();
  env = await initializeTestEnvironment({projectId, firestore: {rules: fs.readFileSync(`${__dirname}/../../firestore.rules`, "utf8")}});
});
after(async () => {
 if (env) await env.cleanup(); if (app) await deleteApp(app);
});
test("participants can read but cannot forge or alter ratings", async () => {
  await db.doc("deliveryRequests/owned").set({senderId: "sender", riderId: "rider", status: "completed", paymentStatus: "paid"});
  await db.doc("driverRatings/owned").set({deliveryId: "owned", customerId: "sender", driverId: "rider", starRating: 5});
  for (const uid of ["sender", "rider", "stranger"]) {
    const client = env.authenticatedContext(uid).firestore();
    await assertFails(setDoc(doc(client, `driverRatings/forged-${uid}`), {customerId: uid, driverId: "victim", starRating: 5}));
    await assertFails(updateDoc(doc(client, "driverRatings/owned"), {starRating: 1, hiddenByAdmin: true}));
    if (uid === "stranger") await assertFails(getDoc(doc(client, "driverRatings/owned")));
    else await assertSucceeds(getDoc(doc(client, "driverRatings/owned")));
  }
});
test("participants cannot invoke moderator actions or reset moderation through report", async () => {
  const ref = db.doc("driverRatings/moderated");
  await ref.set({deliveryId: "moderated", customerId: "sender", driverId: "rider", hiddenByAdmin: true, reportStatus: "investigating", moderationStatus: "hide"});
  for (const uid of ["sender", "rider"]) {
    for (const action of ["hide", "unhide", "investigate"]) {
      await assert.rejects(ratings._test.reportRating({ratingId: ref.id, reason: "Please review", action}, context(uid)), {code: "permission-denied"});
    }
    await ratings._test.reportRating({ratingId: ref.id, reason: "Please review"}, context(uid));
  }
  const saved = (await ref.get()).data();
  assert.equal(saved.hiddenByAdmin, true);
  assert.equal(saved.reportStatus, "investigating");
  assert.equal(saved.moderationStatus, "hide");
  assert.equal((await db.collection("ratingReports").get()).size, 2);
});
test("rating rejects invalid delivery contexts without writing a rating", async () => {
  const valid = {senderId: "sender", riderId: "rider", status: "completed", paymentStatus: "paid", completedAt: new Date()};
  const invalid = [{paymentStatus: "unpaid"}, {status: "cancelled"}, {status: "in_transit"}, {riderId: ""}, {riderId: "sender"}, {senderId: "other"}, {isTest: true}, {refunded: true}];
  for (let i = 0; i < invalid.length; i++) {
    const id = `invalid-${i}`;
    await db.doc(`deliveryRequests/${id}`).set({...valid, ...invalid[i]});
    await assert.rejects(ratings._test.submitRating({deliveryId: id, stars: 5}, context("sender")));
    assert.equal((await db.doc(`driverRatings/${id}`).get()).exists, false);
  }
});
test("50 seeded concurrent rating retries produce one record and aggregate increment", async (t) => {
  const communication = require("./communication-engine");
  t.mock.method(communication, "emitNotification", async () => "test-notification");
  const run = db.runTransaction.bind(db);
  let retries = 0;
  t.mock.method(db, "runTransaction", async (callback, options) => {
    let attempts = 0;
    const result = await run((tx) => {
 attempts++; return callback(tx);
}, options);
    retries += Math.max(0, attempts - 1);
    return result;
  });
  for (let seed = 1; seed <= 50; seed++) {
    const id = `concurrent-${seed}`;
    const riderId = `rider-${seed}`;
    const stars = seed % 5 + 1;
    await db.doc(`deliveryRequests/${id}`).set({senderId: "sender", riderId, status: "completed", paymentStatus: "paid", completedAt: new Date()});
    const results = await Promise.allSettled(Array.from({length: 8}, () => ratings._test.submitRating({deliveryId: id, stars}, context("sender"))));
    assert.equal(results.filter((r) => r.status === "rejected").length, 0, `seed ${seed}: ${JSON.stringify(results)}`);
    const profile = (await db.doc(`riderProfiles/${riderId}`).get()).data();
    assert.equal(profile.totalRatings, 1);
    assert.equal(profile.averageRating, stars);
    assert.equal((await db.collection("driverRatings").where("riderId", "==", riderId).get()).size, 1);
  }
  t.diagnostic(`Terminal passes: 50/50; successful SDK transaction retries: ${retries}`);
});
test("all delivery categories publish only safe rating context and support moderation", async (t) => {
  const communication = require("./communication-engine");
  t.mock.method(communication, "emitNotification", async () => "test-notification");
  const cases = [{serviceType: "standard"}, {serviceType: "health_plus"}, {serviceType: "gift"}, {businessMode: true},
    {isScheduled: true}, {serviceType: "vanguard"}, {serviceType: "heavy"}, {serviceType: "health_plus", isScheduled: true},
    {serviceType: "gift", isScheduled: true}, {businessMode: true, isScheduled: true}, {serviceType: "health_plus", vanguard: true}];
  for (let i = 0; i < cases.length; i++) {
    const id = `category-${i}`;
    await db.doc(`deliveryRequests/${id}`).set({senderId: "sender", riderId: "rider", status: "completed", paymentStatus: "paid", completedAt: new Date(), ...cases[i], prescription: "PRIVATE", giftStory: "PRIVATE", voiceNote: "PRIVATE", invoice: "PRIVATE", address: "PRIVATE"});
    await ratings._test.submitRating({deliveryId: id, stars: 5, feedback: "Very careful and professional."}, context("sender"));
    const published = await assertSucceeds(getDoc(doc(env.authenticatedContext("rider").firestore(), `publishedDriverRatings/${id}`)));
    assert.equal(published.data().feedbackText, "Very careful and professional.");
    assert.equal(JSON.stringify(published.data()).includes("PRIVATE"), false);
    assert.ok(published.data().deliveryCategories.length);
    const expected = [["Standard"], ["Health+"], ["Gift"], ["Business"], ["Scheduled"], ["Vanguard"], ["Heavy"], ["Health+", "Scheduled"], ["Gift", "Scheduled"], ["Business", "Scheduled"], ["Health+", "Vanguard"]][i];
    assert.deepEqual([...published.data().deliveryCategories].sort(), [...expected].sort());
    await assertFails(setDoc(doc(env.authenticatedContext("rider").firestore(), `publishedDriverRatings/${id}`), {feedbackText: "Forged"}, {merge: true}));
    await assertFails(getDoc(doc(env.authenticatedContext("stranger").firestore(), `publishedDriverRatings/${id}`)));
    await assertFails(getDoc(doc(env.authenticatedContext("rider").firestore(), `ratingPrivateFeedback/${id}`)));
  }
  const id = "category-0";
  const admin = {auth: {uid: "moderator", token: {role: "support_agent"}}};
  await ratings._test.reportRating({ratingId: id, reason: "Privacy violation", action: "hide"}, admin);
  assert.equal((await db.doc(`publishedDriverRatings/${id}`).get()).data().feedbackText, "");
  await ratings._test.reportRating({ratingId: id, reason: "Reviewed", action: "unhide"}, admin);
  assert.equal((await db.doc(`publishedDriverRatings/${id}`).get()).data().feedbackText, "Very careful and professional.");
});
test("serious feedback also creates a backend support case", async (t) => {
  t.mock.method(require("./communication-engine"), "emitNotification", async () => "test-notification");
  await db.doc("deliveryRequests/serious").set({senderId: "sender", riderId: "rider", status: "completed", paymentStatus: "paid", completedAt: new Date()});
  await ratings._test.submitRating({deliveryId: "serious", stars: 1, feedbackTags: ["Safety concern"], feedback: "Please contact me."}, context("sender"));
  assert.equal((await db.doc("supportTickets/rating_serious").get()).data().status, "open");
});
test("legacy feedback is republished only after canonical validation and remains moderatable", async () => {
  const riderId = "legacy-rider";
  await db.doc(`riderProfiles/${riderId}`).set({averageRating: 1, totalRatings: 99, riderRank: "existing", trustPoints: 17});
  await db.doc("deliveryRequests/legacy-delivery").set({senderId: "legacy-sender", riderId,
    status: "completed", paymentStatus: "paid", completedAt: new Date(Date.now() - 1000), serviceType: "health_plus", prescription: "PRIVATE"});
  await db.doc("driverRatings/legacy-original").set({deliveryId: "legacy-delivery", customerId: "legacy-sender", driverId: riderId,
    starRating: 5, feedbackText: "Careful delivery.", createdAt: new Date(), prescription: "PRIVATE"});
  await db.doc("driverRatings/legacy-forged").set({deliveryId: "never-delivered", customerId: "legacy-sender", driverId: riderId,
    starRating: 5, feedbackText: "Fake", createdAt: new Date()});
  await assert.rejects(ratings._test.repairRiderRatingFeedback({}, {}), {code: "unauthenticated"});
  const result = await ratings._test.repairRiderRatingFeedback({}, context(riderId));
  assert.equal(result.published, 1);
  assert.equal(result.rejected, 1);
  const stats = (await db.doc(`riderProfiles/${riderId}`).get()).data();
  assert.equal(stats.averageRating, 5);
  assert.equal(stats.totalRatings, 1);
  assert.equal(stats.riderRank, "existing");
  assert.equal(stats.trustPoints, 17);
  const published = (await db.doc("publishedDriverRatings/legacy-delivery").get()).data();
  assert.equal(published.ratingId, "legacy-original");
  assert.equal(published.feedbackText, "Careful delivery.");
  assert.equal(JSON.stringify(published).includes("PRIVATE"), false);
  assert.equal((await ratings._test.repairRiderRatingFeedback({}, context(riderId))).published, 0);
  await ratings._test.reportRating({ratingId: "legacy-original", reason: "Private information", action: "hide"}, {auth: {uid: "support", token: {role: "support_agent"}}});
  assert.equal((await db.doc("publishedDriverRatings/legacy-delivery").get()).data().feedbackText, "");
});
