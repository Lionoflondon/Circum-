/* eslint-disable max-len, require-jsdoc */
"use strict";
const {test} = require("node:test");
const fs = require("node:fs");
const {initializeTestEnvironment, assertFails} = require("@firebase/rules-unit-testing");
const {doc, setDoc, getDoc, deleteDoc} = require("firebase/firestore");
test("compatible deployed rules deny direct QA reads/writes even for allowlisted identities", async () => {
  const env = await initializeTestEnvironment({projectId: "demo-qa-rules", firestore: {rules: fs.readFileSync(`${__dirname}/../../docs/releases/tips-ratings-compatible.firestore.rules`, "utf8")}});
  try {
    for (const uid of ["sender", "rider", "operator", "ordinary"]) {
      const db = env.authenticatedContext(uid).firestore();
      for (const path of ["qaLifecycleFixtures/forged", "qaLifecycleFixtures/forged/deliveryRequests/delivery", "qaLifecycleFixtures/forged/qaProviderObjects/payment", "qaLifecycleFixtures/forged/walletTransactions/earning", "qaLifecycleOperators/operator"]) {
        await assertFails(setDoc(doc(db, path), {isSyntheticQa: true, qaCreatedBy: uid, approvalStatus: "approved"}));
        await assertFails(getDoc(doc(db, path)));
        await assertFails(deleteDoc(doc(db, path)));
      }
    }
  } finally {
 await env.cleanup();
}
});
