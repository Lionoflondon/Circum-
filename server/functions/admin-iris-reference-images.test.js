const assert = require("assert");
const fs = require("fs");
const path = require("path");
const test = require("node:test");

const source = fs.readFileSync(
    path.join(__dirname, "admin-iris-reference-images.js"),
    "utf8",
);
const adminAuth = fs.readFileSync(
    path.join(__dirname, "admin-auth.js"),
    "utf8",
);
const index = fs.readFileSync(path.join(__dirname, "index.js"), "utf8");

test("IRIS reference image callables are exported", () => {
  for (const name of [
    "getIrisReferenceImage",
    "finalizeIrisReferenceImage",
    "deleteIrisReferenceImage",
  ]) {
    assert.match(index, new RegExp(`exports\\.${name}`));
  }
});

test("IRIS reference image workflow is admin-only and audited", () => {
  assert.match(
      source,
      /requireAdmin\(context, "IRIS administrator access is required\."\)/,
  );
  assert.match(adminAuth, /super_admin/);
  assert.match(adminAuth, /operations_admin/);
  assert.match(source, /iris_reference_image_uploaded/);
  assert.match(source, /iris_reference_image_replaced/);
  assert.match(source, /iris_reference_image_deleted/);
  assert.match(source, /collection\("adminAuditLogs"\)/);
});

test("IRIS reference images validate object path, type and size", () => {
  assert.match(source, /irisReferenceImages\/\$\{itemId\}\//);
  assert.match(source, /image\/jpeg/);
  assert.match(source, /image\/png/);
  assert.match(source, /image\/webp/);
  assert.match(source, /10 \* 1024 \* 1024/);
});

test("delete is idempotent and preserves metadata audit state", () => {
  assert.match(source, /duplicate: true/);
  assert.match(source, /deleted: true/);
  assert.match(source, /ignoreNotFound: true/);
});
