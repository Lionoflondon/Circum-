"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const settleConcurrent = require("./test-helpers/settle-concurrent");

test("failed concurrent test waits for every sibling and retains every failure", async () => {
  let finish;
  let ended = false;
  const first = new Error("first failure");
  const second = new Error("second failure");
  const pending = new Promise((resolve) => {
 finish = resolve;
});
  const result = settleConcurrent([Promise.reject(first), pending, Promise.reject(second)]);
  const checked = assert.rejects(result, (error) => {
    assert.deepEqual(error.errors, [first, second]);
    return true;
  }).finally(() => {
 ended = true;
});
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(ended, false);
  finish("completed sibling");
  await checked;
  assert.equal(ended, true);
});

test("successful concurrent test preserves all results in request order", async () => {
  assert.deepEqual(await settleConcurrent([Promise.resolve(1), Promise.resolve(2)]), [1, 2]);
});
