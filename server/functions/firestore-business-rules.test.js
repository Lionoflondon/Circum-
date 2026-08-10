/* eslint-disable max-len, require-jsdoc */
"use strict";

const test = require("node:test");
const fs = require("node:fs");
const path = require("node:path");
const {assertFails, assertSucceeds, initializeTestEnvironment} = require("@firebase/rules-unit-testing");
const {doc, getDoc, setDoc} = require("firebase/firestore");

let env;
test.before(async () => {
  env = await initializeTestEnvironment({projectId: "circum-business-rules-test", firestore: {rules: fs.readFileSync(path.join(__dirname, "..", "..", "firestore.rules"), "utf8")}});
});
test.after(() => env.cleanup());
test.beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, "businessAccounts", "business-1"), {ownerUid: "owner", createdByUserId: "owner"});
    for (const [uid, role] of [["owner", "owner"], ["ops", "operations"], ["finance", "finance"], ["viewer", "viewer"]]) {
      await setDoc(doc(db, "businessMemberships", `business-1_${uid}`), {businessId: "business-1", userId: uid, role, status: "active"});
    }
    await setDoc(doc(db, "businessInvoices", "invoice-1"), {businessId: "business-1", total: 100});
    await setDoc(doc(db, "business_wallets", "business-1"), {businessId: "business-1", balance: 25});
    await setDoc(doc(db, "deliveryRequests", "delivery-1"), {businessId: "business-1", status: "requested"});
    await setDoc(doc(db, "businessCustomRoles", "role-1"), {businessId: "business-1", name: "Warehouse Manager"});
    await setDoc(doc(db, "businessAuditLogs", "audit-1"), {businessId: "business-1", action: "business_custom_role_created"});
  });
});

test("Business finance records are limited to finance-capable roles", async () => {
  for (const uid of ["owner", "finance"]) {
    const db = env.authenticatedContext(uid).firestore();
    await assertSucceeds(getDoc(doc(db, "businessInvoices", "invoice-1")));
    await assertSucceeds(getDoc(doc(db, "business_wallets", "business-1")));
  }
  for (const uid of ["ops", "viewer"]) {
    const db = env.authenticatedContext(uid).firestore();
    await assertFails(getDoc(doc(db, "businessInvoices", "invoice-1")));
    await assertFails(getDoc(doc(db, "business_wallets", "business-1")));
  }
});

test("Business operational members retain delivery access", async () => {
  await assertSucceeds(getDoc(doc(env.authenticatedContext("ops").firestore(), "deliveryRequests", "delivery-1")));
});

test("Custom role and permission audit records are owner-readable and backend-written", async () => {
  const owner = env.authenticatedContext("owner").firestore();
  const ops = env.authenticatedContext("ops").firestore();
  await assertSucceeds(getDoc(doc(owner, "businessCustomRoles", "role-1")));
  await assertSucceeds(getDoc(doc(owner, "businessAuditLogs", "audit-1")));
  await assertFails(getDoc(doc(ops, "businessCustomRoles", "role-1")));
  await assertFails(getDoc(doc(ops, "businessAuditLogs", "audit-1")));
  await assertFails(setDoc(doc(owner, "businessCustomRoles", "role-2"), {businessId: "business-1", name: "Unsafe"}));
});
