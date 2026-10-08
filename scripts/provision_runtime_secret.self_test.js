'use strict';
const assert = require('node:assert/strict');
const {provision} = require('./provision_runtime_secret');
function scenario(responses, value = 'fixture') {
  const calls = [];
  const run = (_, args, options) => {
    calls.push({args, input: options.input});
    assert(responses.length, 'unexpected cloud call');
    return responses.shift();
  };
  const result = provision('RESEND_API_KEY', value, run);
  assert.equal(responses.length, 0);
  return {calls, result};
}
const ok = (text = '') => ({status: 0, stdout: Buffer.from(text)});
const enabled = () => ok('{"state":"ENABLED"}');
let x = scenario([ok(), enabled(), ok('fixture')]);
assert.equal(x.result, 'unchanged');
assert.equal(x.calls.length, 3);
x = scenario([ok(), enabled(), ok('previous'), ok()]);
assert.equal(x.result, 'created');
assert.equal(x.calls.at(-1).input.toString(), 'fixture');
x = scenario([{status: 1, stderr: 'NOT_FOUND'}, ok(), ok()]);
assert.equal(x.result, 'created');
x = scenario([ok(), ok('{"state":"DISABLED"}'), ok()]);
assert.equal(x.result, 'created');
assert.throws(() => scenario([{status: 1, stderr: 'PERMISSION_DENIED'}]), /metadata unavailable/);
assert.throws(() => scenario([ok(), enabled(), {status: 1, stderr: 'PERMISSION_DENIED'}]), /comparison unavailable/);
assert.throws(() => provision('RESEND_API_KEY', ''), /Missing/);
console.log('Secret provisioning: unchanged, changed, missing, disabled and permission failures passed');
