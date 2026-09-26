const fs = require("node:fs");
const test = require("node:test");
const assert = require("node:assert/strict");
const authority = require("./admin-operations-authority");

const source = fs.readFileSync("admin-operations-authority.js", "utf8");

test("Admin cannot create canonical deliveries by duplicating live records", () => {
  assert.doesNotMatch(source, /exports\.adminDuplicateDelivery/);
  assert.doesNotMatch(source, /function duplicateDelivery\(/);
  assert.doesNotMatch(source, /collection\("deliveryRequests"\)\.doc\(newId\)\.set/);
  assert.doesNotMatch(source, /collection\('deliveryRequests'\)\.doc\(newId\)\.set/);
});

test("access resolution reports missing roles without granting access or writing admin records", () => {
  assert.match(source, /async function resolveActor\(context, \{allowMissingRole = false, db = getFirestore\(\)\} = \{\}\)/);
  assert.match(source, /if \(!roles\.size && !allowMissingRole\)/);
  assert.match(source, /resolveActor\(context, \{allowMissingRole: true, db\}\)/);
  assert.match(source, /if \(!actor\.roles\.length\) \{\s*return \{roles: \[\], permissions: \[\], accessGranted: false\};/);
  assert.match(source, /if \(!actor\.roles\.length\)[\s\S]*?return \{roles: \[\], permissions: \[\], accessGranted: false\};[\s\S]*?lastLoginAt/);
});

function fakeDb(initial = {}) {
  const records = new Map(Object.entries(initial));
  const audits = [];
  const ref = (collection, id) => ({
    get: async () => {
      const value = records.get(`${collection}/${id}`);
      return {exists: value !== undefined, data: () => value};
    },
    set: async (value, options = {}) => {
      const key = `${collection}/${id}`;
      records.set(key, options.merge ? {...(records.get(key) || {}), ...value} : {...value});
    },
  });
  return {
    collection: (collection) => ({
      doc: (id) => ref(collection, id),
      add: async (value) => {
        audits.push(value);
        return {id: `audit-${audits.length}`};
      },
    }),
    read: (collection, id) => records.get(`${collection}/${id}`),
    audits,
  };
}

test("Gift editor Cloud Run authority preserves role checks and stamps only real state transitions", async () => {
  const db = fakeDb({"giftRequests/gift-1": {status: "submitted_for_review"}});
  const context = {auth: {uid: "support-1", token: {email: "support@example.invalid", role: "support"}}};
  const result = await authority._private.saveGiftRequestEditor({
    giftId: "gift-1",
    collection: "giftRequests",
    patch: {status: "approved", internalNotes: "fixture"},
    reason: "fixture approval",
  }, context, {db});
  assert.deepEqual(result, {ok: true});
  const saved = db.read("giftRequests", "gift-1");
  assert.equal(saved.status, "approved");
  assert.ok(saved.approvedAt);
  assert.equal(db.audits.length, 1);

  await authority._private.saveGiftRequestEditor({
    giftId: "gift-1",
    collection: "giftRequests",
    patch: {status: "approved"},
    reason: "fixture duplicate",
  }, context, {db});
  assert.equal(db.audits.length, 2);

  await assert.rejects(authority._private.saveGiftRequestEditor({
    giftId: "gift-1", collection: "giftRequests", patch: {status: "rejected"}, reason: "fixture",
  }, {auth: {uid: "viewer", token: {email: "viewer@example.invalid", role: "analytics"}}}, {db}),
  (error) => error.code === "permission-denied");
});
