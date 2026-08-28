/* eslint-disable max-len, no-await-in-loop */
const test = require("node:test");
const fs = require("node:fs");
const path = require("node:path");
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const {
  doc,
  getDoc,
  setDoc,
  updateDoc,
} = require("firebase/firestore");

const projectId = "circum-rules-chat-sender-security-test";
const rules = fs.readFileSync(
    path.join(__dirname, "..", "..", "firestore.rules"),
    "utf8",
);

let testEnv;

test.before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: {rules},
  });
});

test.after(async () => {
  await testEnv.cleanup();
});

test.beforeEach(async () => {
  await testEnv.clearFirestore();
});

async function seedDoc(collection, id, data) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), collection, id), data);
  });
}

function forgedChatPayload(participantId) {
  return {
    conversationType: "sender_rider",
    type: "sender_rider",
    participants: ["sender-a", participantId],
    participantRoles: {
      "sender-a": "sender",
      [participantId]: participantId.startsWith("rider") ? "rider" : "sender",
    },
    createdBy: "sender-a",
    deliveryId: "missing-delivery",
    updatedAt: new Date("2026-08-28T10:00:00Z"),
    createdAt: new Date("2026-08-28T10:00:00Z"),
  };
}

test("clients cannot forge chat metadata by naming arbitrary participants", async () => {
  const db = testEnv.authenticatedContext("sender-a").firestore();
  await assertFails(setDoc(doc(db, "chats", "fake-sender-chat"), forgedChatPayload("sender-b")));
  await assertFails(setDoc(doc(db, "chats", "fake-rider-chat"), forgedChatPayload("rider-b")));
  await assertFails(setDoc(doc(db, "chats", "fake-admin-chat"), forgedChatPayload("admin-user")));
});

test("backend-created chats remain readable only by participants or admins", async () => {
  await seedDoc("chats", "legit-chat", {
    conversationType: "sender_rider",
    participants: ["sender-a", "rider-b"],
    participantRoles: {
      "sender-a": "sender",
      "rider-b": "rider",
    },
    deliveryId: "delivery-1",
    createdAt: new Date("2026-08-28T10:00:00Z"),
    updatedAt: new Date("2026-08-28T10:00:00Z"),
  });

  const senderDb = testEnv.authenticatedContext("sender-a").firestore();
  const riderDb = testEnv.authenticatedContext("rider-b").firestore();
  const adminDb = testEnv.authenticatedContext("admin-user", {roles: ["support_agent"]}).firestore();
  const strangerDb = testEnv.authenticatedContext("stranger").firestore();
  const anonDb = testEnv.unauthenticatedContext().firestore();

  await assertSucceeds(getDoc(doc(senderDb, "chats", "legit-chat")));
  await assertSucceeds(getDoc(doc(riderDb, "chats", "legit-chat")));
  await assertSucceeds(getDoc(doc(adminDb, "chats", "legit-chat")));
  await assertFails(getDoc(doc(strangerDb, "chats", "legit-chat")));
  await assertFails(getDoc(doc(anonDb, "chats", "legit-chat")));
});

test("participants cannot rewrite chat authority fields", async () => {
  await seedDoc("chats", "legit-chat", {
    conversationType: "sender_rider",
    participants: ["sender-a", "rider-b"],
    participantRoles: {
      "sender-a": "sender",
      "rider-b": "rider",
    },
    deliveryId: "delivery-1",
    senderId: "sender-a",
    riderId: "rider-b",
    createdBy: "backend",
    updatedAt: new Date("2026-08-28T10:00:00Z"),
  });
  const db = testEnv.authenticatedContext("sender-a").firestore();
  const chat = doc(db, "chats", "legit-chat");

  for (const patch of [
    {participants: ["sender-a", "rider-b", "victim"]},
    {deliveryId: "other-delivery"},
    {senderId: "victim"},
    {riderId: "victim"},
    {createdBy: "sender-a"},
    {participantRoles: {"sender-a": "admin", "victim": "sender"}},
  ]) {
    await assertFails(updateDoc(chat, patch));
  }
});

test("admin/backend authority can create and update chat metadata", async () => {
  const db = testEnv.authenticatedContext("admin-user", {roles: ["support_agent"]}).firestore();
  const chat = doc(db, "chats", "admin-created-chat");
  await assertSucceeds(setDoc(chat, {
    conversationType: "support",
    participants: ["sender-a", "circum-support"],
    participantRoles: {
      "sender-a": "sender",
      "circum-support": "admin",
    },
    createdAt: new Date("2026-08-28T10:00:00Z"),
    updatedAt: new Date("2026-08-28T10:00:00Z"),
  }));
  await assertSucceeds(updateDoc(chat, {lastMessage: "Handled by support."}));
});

test("sender self-writes cannot create privileged sender fields", async () => {
  const base = {displayName: "Sender A", preferences: {email: true}};

  for (const field of [
    "role",
    "roles",
    "adminRole",
    "isAdmin",
    "verificationStatus",
    "approvalStatus",
    "dispatchEligible",
    "accountStatus",
    "permissions",
    "claims",
    "customClaims",
    "financialAuthority",
    "paymentAuthority",
    "reviewStatus",
    "adminReviewStatus",
  ]) {
    const senderId = `sender-create-${field}`;
    const db = testEnv.authenticatedContext(senderId).firestore();
    await assertFails(setDoc(doc(db, "senders", senderId), {
      ...base,
      [field]: field === "roles" ? ["super_admin"] : "forged",
    }));
  }
});

test("sender self-writes cannot update privileged sender fields", async () => {
  await seedDoc("senders", "sender-a", {
    displayName: "Sender A",
    preferences: {email: true},
    createdAt: new Date("2026-08-28T10:00:00Z"),
  });
  const db = testEnv.authenticatedContext("sender-a").firestore();
  const senderRef = doc(db, "senders", "sender-a");

  for (const field of [
    "role",
    "roles",
    "adminRole",
    "isAdmin",
    "verificationStatus",
    "approvalStatus",
    "dispatchEligible",
    "accountStatus",
    "permissions",
    "claims",
    "customClaims",
    "financialAuthority",
    "paymentAuthority",
    "reviewStatus",
    "adminReviewStatus",
  ]) {
    await assertFails(updateDoc(senderRef, {
      [field]: field === "roles" ? ["super_admin"] : "forged",
    }));
  }
});

test("ordinary sender profile edits and admin authority remain intact", async () => {
  await seedDoc("senders", "sender-a", {
    displayName: "Sender A",
    preferences: {email: true},
    createdAt: new Date("2026-08-28T10:00:00Z"),
  });
  const senderDb = testEnv.authenticatedContext("sender-a").firestore();
  const otherDb = testEnv.authenticatedContext("sender-b").firestore();
  const adminDb = testEnv.authenticatedContext("admin-user", {roles: ["support_agent"]}).firestore();

  await assertSucceeds(updateDoc(doc(senderDb, "senders", "sender-a"), {
    displayName: "Sender A Updated",
    preferences: {email: false},
  }));
  const freshSenderDb = testEnv.authenticatedContext("new-sender-a").firestore();
  await assertSucceeds(setDoc(doc(freshSenderDb, "senders", "new-sender-a"), {
    displayName: "Sender A",
    preferences: {sms: true},
  }));
  await assertFails(updateDoc(doc(otherDb, "senders", "sender-a"), {
    displayName: "Hijacked",
  }));
  await assertFails(getDoc(doc(testEnv.unauthenticatedContext().firestore(), "senders", "sender-a")));
  await assertSucceeds(updateDoc(doc(adminDb, "senders", "sender-a"), {
    verificationStatus: "verified",
  }));
});
