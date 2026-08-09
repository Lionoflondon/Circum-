/* eslint-disable max-len, require-jsdoc */
const test = require("node:test");
const fs = require("node:fs");
const path = require("node:path");
const {assertFails, assertSucceeds, initializeTestEnvironment} = require("@firebase/rules-unit-testing");
const {doc, getDoc, setDoc, updateDoc} = require("firebase/firestore");

let env;
test.before(async () => {
  env = await initializeTestEnvironment({
    projectId: "circum-communications-rules-test",
    firestore: {rules: fs.readFileSync(path.join(__dirname, "..", "..", "firestore.rules"), "utf8")},
  });
});
test.after(() => env.cleanup());
test.beforeEach(() => env.clearFirestore());

async function seedCommunications() {
  await env.withSecurityRulesDisabled(async (context) => {
    const firestore = context.firestore();
    await setDoc(doc(firestore, "chats", "delivery-1"), {
      conversationType: "sender_rider",
      participants: ["sender-1", "rider-1", "circum-support"],
      participantRoles: {"sender-1": "sender", "rider-1": "rider", "circum-support": "admin"},
    });
    await setDoc(doc(firestore, "chats", "delivery-1", "messages", "message-1"), {
      senderId: "sender-1",
      message: "Operational update",
    });
    await setDoc(doc(firestore, "notifications", "notification-1"), {
      recipientId: "sender-1",
      recipientRole: "sender",
      title: "Delivery update",
      body: "Your Rider is on the way.",
      read: false,
    });
    await setDoc(doc(firestore, "healthPlusNotifications", "health-1"), {
      senderId: "sender-1",
      userId: "sender-1",
      title: "Health+ update",
    });
  });
}

test("declared Sender and assigned Rider can read their delivery chat", async () => {
  await seedCommunications();
  await assertSucceeds(getDoc(doc(env.authenticatedContext("sender-1").firestore(), "chats", "delivery-1")));
  await assertSucceeds(getDoc(doc(env.authenticatedContext("rider-1").firestore(), "chats", "delivery-1")));
});

test("unrelated and former Riders cannot read another delivery chat", async () => {
  await seedCommunications();
  await assertFails(getDoc(doc(env.authenticatedContext("rider-2").firestore(), "chats", "delivery-1")));
  await assertFails(getDoc(doc(env.authenticatedContext("former-rider").firestore(), "chats", "delivery-1")));
});

test("participants cannot forge chats or rewrite participant authority", async () => {
  await seedCommunications();
  const senderDb = env.authenticatedContext("sender-1").firestore();
  await assertFails(setDoc(doc(senderDb, "chats", "forged-chat"), {
    participants: ["sender-1", "victim"],
  }));
  await assertFails(updateDoc(doc(senderDb, "chats", "delivery-1"), {
    participants: ["sender-1", "rider-1", "attacker"],
  }));
});

test("clients cannot write message documents directly", async () => {
  await seedCommunications();
  await assertFails(setDoc(
      doc(env.authenticatedContext("sender-1").firestore(), "chats", "delivery-1", "messages", "forged-message"),
      {senderId: "sender-1", message: "forged"},
  ));
});

test("message history is restricted to the canonical participants", async () => {
  await seedCommunications();
  await assertSucceeds(getDoc(doc(env.authenticatedContext("rider-1").firestore(), "chats", "delivery-1", "messages", "message-1")));
  await assertFails(getDoc(doc(env.authenticatedContext("rider-2").firestore(), "chats", "delivery-1", "messages", "message-1")));
});

test("notification recipients can read but cannot rewrite notification authority", async () => {
  await seedCommunications();
  const senderDb = env.authenticatedContext("sender-1").firestore();
  await assertSucceeds(getDoc(doc(senderDb, "notifications", "notification-1")));
  await assertFails(updateDoc(doc(senderDb, "notifications", "notification-1"), {
    recipientId: "attacker",
    body: "forged",
  }));
  await assertFails(getDoc(doc(env.authenticatedContext("rider-1").firestore(), "notifications", "notification-1")));
});

test("even privileged clients cannot create backend notification events", async () => {
  await seedCommunications();
  const adminDb = env.authenticatedContext("admin-1", {adminRole: "super_admin"}).firestore();
  await assertFails(setDoc(doc(adminDb, "notifications", "forged"), {
    recipientId: "victim",
    title: "forged",
  }));
});

test("Health+ notification records are readable by their owner but backend-authored only", async () => {
  await seedCommunications();
  const senderDb = env.authenticatedContext("sender-1").firestore();
  await assertSucceeds(getDoc(doc(senderDb, "healthPlusNotifications", "health-1")));
  await assertFails(setDoc(doc(senderDb, "healthPlusNotifications", "forged"), {
    senderId: "sender-1",
    userId: "sender-1",
    title: "forged",
  }));
});
