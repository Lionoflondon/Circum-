/* eslint-disable max-len, require-jsdoc */
"use strict";
const test = require("node:test"); const assert = require("node:assert/strict"); const {certify} = require("./private-qa-cleanup-certifier");
test("private QA certification forwards only an explicit disposable fixture to the existing owner", async () => {
  let calls = 0;
  const get = async () => ({request: async (request) => {
calls++; assert.equal(request.url, "https://circum-qa-special-flow-j2b7cicfwq-uc.a.run.app/recovery/expireQaLifecycleFixtures/fixture"); assert.deepEqual(request.data, {fixtureId: "__codex_test"}); return {data: {ok: true}};
}});
  assert.deepEqual(await certify({worker: "expireQaLifecycleFixtures", fixtureId: "__codex_test"}, get), {ok: true});
  for (const input of [{worker: "processNoShowSettlementRetries", fixtureId: "__codex_test"}, {worker: "expireQaLifecycleFixtures", fixtureId: "customer"}]) await assert.rejects(certify(input, get), {statusCode: 400});
  assert.equal(calls, 1);
});
