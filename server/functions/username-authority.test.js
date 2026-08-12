const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const authority = require("./username-authority")._test;

test("username normalization is deterministic and case insensitive", () => {
  assert.equal(authority.normalizeUsername("  @Jason  "), "jason");
  assert.equal(authority.normalizeUsername("@@NIKE_ADESANYA"), "nike_adesanya");
});

test("username policy rejects invalid, reserved, Unicode, and oversized handles", () => {
  for (const value of ["", "ab", "circum", "Jason Smith", "jason!", "jаson", "a".repeat(31)]) {
    assert.equal(authority.validateUsername(value).valid, false, value);
  }
  assert.deepEqual(authority.validateUsername("@Jason_27"), {valid: true, username: "jason_27"});
});

test("username claim is one Firestore transaction and retains previous handles", () => {
  const source = fs.readFileSync("username-authority.js", "utf8");
  assert.match(source, /db\.runTransaction/);
  assert.match(source, /targetSnapshot\.exists && targetSnapshot\.data\(\)\.uid !== uid/);
  assert.match(source, /status: "retained"/);
  assert.match(source, /enforceAppCheck: true/);
  assert.match(source, /claimCircumUsername/);
  assert.match(source, /riderProfiles/);
});

test("general profile mutation cannot establish username authority", () => {
  const account = fs.readFileSync("sender-account.js", "utf8");
  const rules = fs.readFileSync("../../firestore.rules", "utf8");
  assert.doesNotMatch(account, /patch\.username/);
  assert.match(account, /exports\.updateSenderProfile = functions\.runWith\(\{enforceAppCheck: true\}\)/);
  assert.match(rules, /affectedKeys\(\)\.hasAny\(\['username', 'usernameCanonical', 'usernameUpdatedAt', 'handle'\]\)/);
  assert.match(rules, /match \/usernames\/\{username\}[\s\S]*allow create, update, delete: if false;/);
  assert.doesNotMatch(rules.match(/function riderSelfWritableFields\(\)[\s\S]*?\n {4}\}/)[0], /'username'|'handle'/);
});

function fakeFirestore(seed = {}) {
  const records = new Map(Object.entries(seed));
  let queue = Promise.resolve();
  const ref = (path) => ({path});
  const db = {
    collection(name) {
      return {doc(id = `event-${records.size}`) {
 return ref(`${name}/${id}`);
}};
    },
    runTransaction(work) {
      const run = queue.then(async () => {
        const writes = [];
        const transaction = {
          async get(document) {
            const value = records.get(document.path);
            return {exists: value !== undefined, data: () => value};
          },
          set(document, value, options) {
 writes.push({document, value, options});
},
        };
        const result = await work(transaction);
        for (const write of writes) {
          records.set(write.document.path, {
            ...(write.options && write.options.merge ? records.get(write.document.path) : {}),
            ...write.value,
          });
        }
        return result;
      });
      queue = run.catch(() => {});
      return run;
    },
  };
  return {db, records};
}

test("case variants cannot win concurrent claims", async () => {
  const store = fakeFirestore();
  const claims = await Promise.allSettled([
    authority.claimUsername({username: "@Jason"}, {auth: {uid: "user-a"}}, {db: store.db}),
    authority.claimUsername({username: "jason"}, {auth: {uid: "user-b"}}, {db: store.db}),
  ]);
  assert.equal(claims.filter((claim) => claim.status === "fulfilled").length, 1);
  assert.equal(claims.filter((claim) => claim.status === "rejected").length, 1);
  assert.equal(store.records.get("usernames/jason").uid, "user-a");
});

test("changing a handle retains the old canonical name", async () => {
  const store = fakeFirestore({
    "users/user-a": {username: "first_name"},
    "usernames/first_name": {uid: "user-a", status: "active", current: true},
  });
  await authority.claimUsername({username: "Second_Name"}, {auth: {uid: "user-a"}}, {db: store.db});
  assert.equal(store.records.get("usernames/first_name").status, "retained");
  assert.equal(store.records.get("usernames/second_name").uid, "user-a");
  assert.equal(store.records.get("users/user-a").username, "second_name");
});

test("a Rider username claim projects the canonical handle to Rider profiles", async () => {
  const store = fakeFirestore({
    "riders/rider-a": {approvalStatus: "approved"},
    "riderProfiles/rider-a": {name: "Ayo Jason"},
  });
  await authority.claimUsername(
      {username: "Ayo_Jason"},
      {auth: {uid: "rider-a"}},
      {db: store.db},
  );
  assert.equal(store.records.get("riders/rider-a").username, "ayo_jason");
  assert.equal(store.records.get("riderProfiles/rider-a").canonicalUsername, "ayo_jason");
});
