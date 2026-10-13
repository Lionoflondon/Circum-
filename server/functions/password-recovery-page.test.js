"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const page = import("../../web/reset-password/recovery.mjs");
const valid = "https://circumuk.com/reset-password/#mode=resetPassword&oobCode=example-code-12345678901234567890&app=sender";

test("recovery page rejects duplicate, missing, tampered and arbitrary redirect inputs", async () => {
  const {parseRecoveryLink} = await page;
  for (const value of [valid + "&continueUrl=https://evil.test", valid + "&app=rider", valid.replace("resetPassword", "verifyEmail"), valid.replace("app=sender", "app=__proto__"), valid.replace("/#", "/?secret=x#"), valid.replace("oobCode=example-code-12345678901234567890", "oobCode=short")]) assert.throws(() => parseRecoveryLink(value));
  assert.equal(parseRecoveryLink(valid).returnPath, "/send/profile");
  assert.equal(parseRecoveryLink(valid.replace("app=sender", "app=rider")).returnPath, "/rider?access=login");
});

test("page validates the live password policy and confirmation before the single-use Firebase operation", async () => {
  const {createRecoveryFlow} = await page; let applied = 0;
  const flow = createRecoveryFlow({verify: async () => {}, validate: async (password) => ({isValid: password.length >= 10, passwordPolicy: {customStrengthOptions: {minPasswordLength: 10, containsNumericCharacter: true}}}), confirm: async () => {
applied++;
}});
  assert.deepEqual(await flow.open("opaque"), ["Between 10 and 4096 characters", "At least one number"]);
  assert.equal((await flow.submit("short", "short")).ok, false);
  assert.equal((await flow.submit("tencharacters", "different")).ok, false);
  assert.equal(applied, 0);
  assert.equal((await flow.submit("tencharacters", "tencharacters")).ok, true);
  await assert.rejects(flow.submit("tencharacters", "tencharacters")); assert.equal(applied, 1);
});

for (const code of ["auth/expired-action-code", "auth/invalid-action-code", "auth/user-disabled", "auth/user-not-found"]) {
test(`safe terminal UI for ${code}`, async () => {
  const {createRecoveryFlow, recoveryError} = await page;
  const error = Object.assign(Error("private detail"), {code});
  const flow = createRecoveryFlow({verify: async () => {
throw error;
}, validate: () => assert.fail(), confirm: () => assert.fail()});
  await assert.rejects(flow.open("code")); await assert.rejects(flow.submit("a", "a"));
  assert.equal(recoveryError(error).terminal, true); assert.doesNotMatch(recoveryError(error).message, /private detail/);
});
}

test("provider uncertainty and double submit cannot apply two changes concurrently", async () => {
  const {createRecoveryFlow} = await page; let release; let count = 0;
  const flow = createRecoveryFlow({verify: async () => {}, validate: async () => ({isValid: true}), confirm: async () => {
count++; await new Promise((r) => {
 release = r;
});
}});
  await flow.open("code"); const first = flow.submit("longpassword", "longpassword");
  await new Promise(setImmediate); await assert.rejects(flow.submit("longpassword", "longpassword")); release(); await first; assert.equal(count, 1);
});
