/* eslint-disable max-len, require-jsdoc */
const {test, before, after, mock} = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");
const {initializeTestEnvironment, assertFails, assertSucceeds} = require("@firebase/rules-unit-testing");
const {doc, getDoc, setDoc, updateDoc, deleteDoc} = require("firebase/firestore");
const engine = require("./communication-engine");
const notifications = require("./platform-notifications");
const sender = require("./sender-account");
const rider = require("./rider-account");
let app; let db; let env; let sends = 0; let adminSends = 0;
const ctx = (uid) => ({auth: {uid, token: {email: `${uid}@example.invalid`, name: "Test participant"}}});
const client = (uid, role = "user") => env.authenticatedContext(uid, {role, adminRole: role, roles: [role]}).firestore();
before(async () => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, "This suite must never connect to production.");
  const projectId = "demo-chat-notification";
  app = initializeApp({projectId}); db = getFirestore();
  mock.method(getMessaging(), "send", async () => {
 sends++; return "test-push";
});
  mock.method(getMessaging(), "sendEachForMulticast", async () => {
 adminSends++; return {successCount: 1, failureCount: 0};
});
  env = await initializeTestEnvironment({projectId, firestore: {rules: fs.readFileSync(process.env.CHAT_NOTIFICATION_RULES_PATH || `${__dirname}/../../firestore.rules`, "utf8")}});
});
after(async () => {
 mock.restoreAll(); if (env) await env.cleanup(); if (app) await deleteApp(app);
});

test("notification recipients read privately but only admins can author records", async () => {
  const path = "notifications/authority";
  await db.doc(path).set({recipientId: "owner", title: "Original", body: "Original", data: {}, read: false});
  await assertSucceeds(getDoc(doc(client("owner"), path)));
  await assertFails(getDoc(doc(client("stranger"), path)));
  for (const patch of [{title: "Forged"}, {body: "Forged"}, {data: {route: "admin"}}, {recipientId: "stranger"}, {read: true}, {archived: true}]) {
    await assertFails(updateDoc(doc(client("owner"), path), patch));
  }
  await assertFails(setDoc(doc(client("owner"), "notifications/new"), {recipientId: "owner", title: "Forged"}));
  await assertFails(deleteDoc(doc(client("owner"), path)));
  await assertSucceeds(getDoc(doc(client("admin", "operations_admin"), path)));
  await assertSucceeds(updateDoc(doc(client("admin", "operations_admin"), path), {title: "Admin edit"}));
  await assertSucceeds(setDoc(doc(client("admin", "operations_admin"), "notifications/admin-authored"), {recipientId: "owner"}));
  await assertFails(deleteDoc(doc(client("admin", "operations_admin"), path)));
  await assertSucceeds(deleteDoc(doc(client("founder-test", "super_admin"), path)));
});

test("Sender and Rider safe callables preserve notification content while updating read/archive/delete state", async () => {
  for (const role of ["sender", "rider"]) {
    const uid = `state-${role}`; const id = `notification-${role}`;
    const ref = db.doc(`notifications/${id}`);
    await ref.set({recipientId: uid, recipientRole: role, title: "Original", body: "Original", data: {route: "conversation"}, read: false});
    const callable = role === "sender" ? sender.updateSenderNotificationState : rider.updateRiderNotificationState;
    for (const action of ["mark_read", "archive", "delete"]) {
      await assert.rejects(callable.run({notificationId: id, action}, ctx("stranger")), {code: "permission-denied"});
      await callable.run({notificationId: id, action, title: "Injected", recipientId: "stranger"}, ctx(uid));
      const saved = (await ref.get()).data();
      assert.equal(saved.title, "Original"); assert.equal(saved.body, "Original"); assert.equal(saved.recipientId, uid);
    }
    const saved = (await ref.get()).data();
    assert.equal(saved.read, true); assert.equal(saved.archived, true); assert.ok(saved.deletedAt);
    await assert.rejects(callable.run({notificationId: id, action: "change_title"}, ctx(uid)), {code: "invalid-argument"});
  }
});

test("website support masks contact details in stored ticket and chat message content", async () => {
  for (const context of [{}, ctx("support-owner")]) {
    const result = await engine.submitWebsiteSupportRequest.run({email: "reply@example.invalid", message: "Please help: person@example.com or +44 7700 900123"}, context);
    const ticket = (await db.doc(`supportTickets/${result.ticketId}`).get()).data();
    assert.equal(ticket.message, "Please help: [email removed] or [phone number removed]");
    assert.equal(ticket.lastMessage, ticket.message);
    // The form's explicit reply address stays in the support ticket, not chat content.
    assert.equal(ticket.email, "reply@example.invalid");
    if (context.auth) {
      const message = (await db.doc(`chats/${result.chatId}/messages/ticket_initial`).get()).data();
      assert.equal(message.messageText || message.message, ticket.message);
      assert.equal((await db.doc(`chats/${result.chatId}`).get()).data().lastMessage, ticket.message);
    }
  }
});

test("chat messages stay backend-authored; participants send/read through callables and strangers are denied", async () => {
  const chatId = "private-chat";
  await db.doc(`chats/${chatId}`).set({participants: ["chat-owner", "chat-peer"], participantRoles: {"chat-owner": "sender", "chat-peer": "rider"}, conversationType: "sender_rider"});
  const result = await engine.sendCircumMessage.run({chatId, message: "Hello person@example.com"}, ctx("chat-owner"));
  const path = `chats/${chatId}/messages/${result.messageId}`;
  assert.equal((await db.doc(path).get()).data().messageText, "Hello [email removed]");
  await assertSucceeds(getDoc(doc(client("chat-peer"), path)));
  await assertFails(getDoc(doc(client("stranger"), path)));
  for (const uid of ["chat-owner", "stranger"]) await assertFails(setDoc(doc(client(uid), `chats/${chatId}/messages/forged`), {senderId: uid, message: "Forged"}));
  await assertFails(updateDoc(doc(client("chat-owner"), path), {messageText: "Forged"}));
  await assertFails(deleteDoc(doc(client("chat-owner"), path)));
  await assert.rejects(engine.sendCircumMessage.run({chatId, message: "Forbidden"}, ctx("stranger")), {code: "permission-denied"});
  await engine.markConversationRead.run({chatId}, ctx("chat-peer"));
  await engine.setConversationTyping.run({chatId, typing: true}, ctx("chat-peer"));
  await assert.rejects(engine.setConversationTyping.run({chatId, typing: true}, ctx("stranger")), {code: "permission-denied"});
});

test("chat trigger replay deduplicates each recipient and admin record and push attempt", async () => {
  await db.doc("users/recipient").set({fcmToken: "test-sender-token"});
  await db.doc("riderProfiles/recipient-rider").set({fcmToken: "test-rider-token"});
  await db.doc("adminUsers/admin").set({fcmToken: "test-admin-token"});
  const chatId = "dedupe-chat";
  await db.doc(`chats/${chatId}`).set({type: "support", participants: ["author", "recipient", "recipient-rider", "circum-support"], participantRoles: {"recipient-rider": "rider"}});
  const trigger = (messageId) => notifications.onChatMessageCreated.run({data: () => ({senderId: "author", senderRole: "sender", messageText: "Hello"})}, {params: {chatId, messageId}});
  await Promise.all([trigger("message-1"), trigger("message-1"), trigger("message-1")]);
  assert.equal(sends, 2); assert.equal(adminSends, 1);
  for (const uid of ["recipient", "recipient-rider", "admin"]) {
    const key = `${chatId}:message-1:chat:${uid}`;
    const id = `event_${Buffer.from(key).toString("base64url")}`;
    assert.equal((await db.doc(`notifications/${id}`).get()).data().dedupeKey, key);
  }
  const id = `event_${Buffer.from(`${chatId}:message-1:chat:recipient`).toString("base64url")}`;
  await sender.updateSenderNotificationState.run({notificationId: id, action: "mark_read"}, ctx("recipient"));
  await trigger("message-1");
  assert.equal((await db.doc(`notifications/${id}`).get()).data().read, true);
  assert.equal(sends, 2); assert.equal(adminSends, 1);
  await trigger("message-2");
  assert.equal(sends, 4); assert.equal(adminSends, 2);
});
