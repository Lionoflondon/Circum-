const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const template = JSON.parse(fs.readFileSync(path.join(__dirname, "templates/verify-email.json"), "utf8"));
test("Sender and Rider shared Firebase verification email hides action details in displayed content", () => {
  const action = "https://circum-2797c.firebaseapp.com/__/auth/action?apiKey=test&oobCode=single-use";
  const rendered = template.body.replaceAll("%LINK%", action).replaceAll("%DISPLAY_NAME%", "Test");
  const visible = rendered.replace(/<[^>]*>/g, "");
  for (const detail of ["firebaseapp.com", "/__/auth/action", "apiKey=", "oobCode="]) assert.equal(visible.includes(detail), false);
  assert.match(visible, /Verify email/);
  assert.equal((rendered.match(/href="https:\/\/circum-2797c\.firebaseapp\.com/g) || []).length, 2);
  assert.equal(template.bodyFormat, "HTML");
});
test("verification template contains only supported placeholders and Circum sender branding", () => {
  assert.deepEqual([...new Set(template.body.match(/%[A-Z_]+%/g))].sort(), ["%DISPLAY_NAME%", "%LINK%"]);
  assert.equal(template.senderDisplayName, "Circum");
  assert.equal(template.subject, "Verify your email for Circum");
});

const {buildVerificationEmail, createVerificationEmailHandler} = require("./verification-email");
test("rendered email hides provider details in visible HTML and plaintext", () => {
  const email = buildVerificationEmail("https://circum-2797c.firebaseapp.com/__/auth/action?mode=verifyEmail&apiKey=test&oobCode=single-use");
  for (const body of [email.html.replace(/<[^>]*>/g, ""), email.text]) for (const detail of ["firebaseapp.com", "/__/auth/action", "apiKey=", "oobCode="]) assert.equal(body.includes(detail), false);
  assert.match(email.html, />Verify email<\/a>/);
  assert.match(email.html, /&amp;apiKey=/);
  assert.throws(() => buildVerificationEmail("https://attacker.example/verify"), /Invalid verification link/);
});
test("verified accounts send nothing and recipient is read from Auth, not client input", async () => {
  let requested;
  const handler = createVerificationEmailHandler({auth: () => ({getUser: async (uid) => {
requested=uid; return {email: "real@example.test", emailVerified: true};
}}), db: ()=>{
throw Error("Unexpected write");
}});
  assert.deepEqual(await handler({email: "attacker@example.test"}, {auth: {uid: "sender"}}), {ok: true, alreadyVerified: true});
  assert.equal(requested, "sender");
  await assert.rejects(handler({}, {}), {code: "unauthenticated"});
});

for (const role of ["sender", "rider"]) {
test(`${role} queues a branded email for the authoritative recipient and bounds resends`, async () => {
  let state;
  let queued;
  let generated = 0;
  const database = {
    collection: (name) => ({doc: (id) => ({name, id, create: async (data) => {
queued = data;
}})}),
    runTransaction: async (run) => run({get: async () => ({exists: !!state, data: () => state}), set: (_ref, data) => {
state = data;
}}),
  };
  const handler = createVerificationEmailHandler({
    auth: () => ({getUser: async (uid) => ({uid, email: `${role}@example.test`, emailVerified: false}), generateEmailVerificationLink: async (email) => {
      assert.equal(email, `${role}@example.test`);
      generated++;
      return "https://circum-2797c.firebaseapp.com/__/auth/action?mode=verifyEmail&apiKey=test&oobCode=secret";
    }}), db: () => database, now: () => 100000, randomId: () => "test",
  });
  assert.deepEqual(await handler({email: "attacker@example.test"}, {auth: {uid: role}}), {ok: true, queued: true});
  assert.equal(queued.to, `${role}@example.test`);
  assert.equal(queued.maxAttempts, 5);
  assert.equal(queued.sourceCollection, "authVerificationRequests");
  assert.equal(queued.sourceDocumentId, role);
  assert.equal(queued.notificationId, `verify_email_${role}_test`);
  assert.match(queued.html, />Verify email</);
  await assert.rejects(handler({}, {auth: {uid: role}}), {code: "resource-exhausted"});
  assert.equal(generated, 1);
});
}
test("disabled accounts cannot enqueue mail", async () => {
  const handler = createVerificationEmailHandler({auth: () => ({getUser: async () => ({disabled: true, email: "disabled@example.test"})}), db: () => {
throw Error("Unexpected write");
}});
  await assert.rejects(handler({}, {auth: {uid: "disabled"}}), {code: "failed-precondition"});
});
