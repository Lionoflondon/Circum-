/* eslint-disable max-len */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {OPERATIONS} = require("./cloud-run-native-callable-proxy");
const root = path.join(__dirname, "..", "..");
const transport = fs.readFileSync(path.join(root, "lib/app/sender_mobile/business_health_callable_api.dart"), "utf8");

test("next native Business/Health routes and App Check requirements match deployed owner contracts", () => {
  const routes = [...transport.matchAll(/'([A-Za-z]+)':\s*'(https:\/\/[^']+)'/g)];
  assert.equal(routes.length, 24);
  const required = transport.match(/const _requiresAppCheck = <String>\{([\s\S]*?)\}/)[1];
  for (const [, operation, url] of routes) {
    const policy = OPERATIONS[operation];
    assert.ok(policy, operation);
    assert.equal(url, `https://${policy.owner}-j2b7cicfwq-uc.a.run.app/${policy.path !== undefined ? policy.path : operation}`);
    assert.equal(required.includes(`'${operation}'`), Boolean(policy.appCheck), `${operation} App Check policy`);
  }
  for (const file of ["lib/app/business/business_repository.dart", "lib/app/health_plus/view/health_plus.dart", "lib/app/admin/admin_phase1_shell.dart"]) {
    const source = fs.readFileSync(path.join(root, file), "utf8");
    for (const [, operation] of routes) {
      assert.ok(!source.includes(`.httpsCallable('${operation}')`), `${file} must not use the failed ${operation} SDK endpoint`);
    }
  }
});
