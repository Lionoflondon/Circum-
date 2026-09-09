/* eslint-disable max-len */
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {initializeTestEnvironment, assertFails, assertSucceeds} = require("@firebase/rules-unit-testing");
const {doc, getDoc, setDoc, updateDoc} = require("firebase/firestore");

const projectId = `admin-rules-${process.pid}`;
let env;

test.before(async () => {
  env = await initializeTestEnvironment({
    projectId,
    firestore: {rules: fs.readFileSync(path.join(__dirname, "../../firestore.rules"), "utf8")},
  });
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, "payments/payment-1"), {senderId: "sender-1", amountMinor: 1000});
    await setDoc(doc(db, "supportTickets/ticket-1"), {status: "open", userId: "sender-1"});
    await setDoc(doc(db, "healthPlusProfiles/health-1"), {senderId: "sender-1", status: "active"});
    await setDoc(doc(db, "riderApplications/rider-1"), {riderId: "rider-1", approvalStatus: "pending"});
    await setDoc(doc(db, "wallets/wallet-1"), {userId: "sender-1", balance: 5});
  });
});

test.after(async () => env && env.cleanup());

function db(uid, claims) {
  return env.authenticatedContext(uid, claims).firestore();
}

test("finance Admin can read finance but not support or Health+", async () => {
  const finance = db("finance", {adminRole: "finance_admin"});
  await assertSucceeds(getDoc(doc(finance, "payments/payment-1")));
  await assertFails(getDoc(doc(finance, "supportTickets/ticket-1")));
  await assertFails(getDoc(doc(finance, "healthPlusProfiles/health-1")));
});

test("support Admin reads support but not finance", async () => {
  const support = db("support", {role: "support_agent"});
  await assertSucceeds(getDoc(doc(support, "supportTickets/ticket-1")));
  await assertFails(getDoc(doc(support, "payments/payment-1")));
  await assertFails(getDoc(doc(support, "wallets/wallet-1")));
});

test("Rider reviewer reads applications but not finance", async () => {
  const reviewer = db("reviewer", {roles: ["reviewer"]});
  await assertSucceeds(getDoc(doc(reviewer, "riderApplications/rider-1")));
  await assertFails(getDoc(doc(reviewer, "payments/payment-1")));
});

test("Admin clients cannot directly mutate sensitive records", async () => {
  for (const claims of [
    {adminRole: "finance_admin"},
    {adminRole: "operations_admin"},
    {role: "super_admin"},
  ]) {
    const admin = db(`admin-${claims.adminRole || claims.role}`, claims);
    await assertFails(updateDoc(doc(admin, "payments/payment-1"), {amountMinor: 1}));
    await assertFails(updateDoc(doc(admin, "wallets/wallet-1"), {balance: 999}));
    await assertFails(updateDoc(doc(admin, "riderApplications/rider-1"), {approvalStatus: "approved"}));
  }
});
