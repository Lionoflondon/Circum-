"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  getGiftStoryOwner,
  isGiftStoryOwner,
  runGiftStoryEffect,
} = require("./gift-story-completion-core");

function fakeDb(initial = {}) {
  const values = new Map(Object.entries(initial));
  let transactionQueue = Promise.resolve();
  const ref = (path) => ({
    id: path.split("/").at(-1),
    get: async () => ({
      exists: values.has(path),
      data: () => values.get(path),
    }),
    set: async (value, options = {}) => values.set(path, options.merge ? {...(values.get(path) || {}), ...value} : value),
  });
  return {
    collection: (name) => ({doc: (id) => ref(`${name}/${id}`)}),
    runTransaction: (callback) => {
      const run = async () => {
        const writes = [];
        const transaction = {
          get: (document) => document.get(),
          set: (document, value, options) => writes.push({document, value, options}),
        };
        const result = await callback(transaction);
        for (const write of writes) await write.document.set(write.value, write.options);
        return result;
      };
      const pending = transactionQueue.then(run);
      transactionQueue = pending.catch(() => {});
      return pending;
    },
    read: (path) => values.get(path),
    delete: (path) => values.delete(path),
  };
}

test("Gift Story ownership defaults to the existing Firestore owner and fails closed on invalid values", async () => {
  const db = fakeDb();
  assert.equal(await getGiftStoryOwner(db), "firestore");
  assert.equal(await isGiftStoryOwner(db, "firestore"), true);
  assert.equal(await isGiftStoryOwner(db, "cloud_run"), false);
  const configured = fakeDb({"runtimeOwnership/giftStoryCompletion": {owner: "invalid"}});
  assert.equal(await getGiftStoryOwner(configured), "none");
});

test("Gift Story ownership override is bounded to valid preflight states", async () => {
  const previous = process.env.GIFT_STORY_OWNER_OVERRIDE;
  try {
    process.env.GIFT_STORY_OWNER_OVERRIDE = "cloud_run";
    assert.equal(await getGiftStoryOwner(fakeDb()), "cloud_run");
    assert.equal(await isGiftStoryOwner(fakeDb(), "cloud_run"), true);
    process.env.GIFT_STORY_OWNER_OVERRIDE = "none";
    assert.equal(await getGiftStoryOwner(fakeDb()), "none");
    process.env.GIFT_STORY_OWNER_OVERRIDE = "invalid";
    assert.equal(await getGiftStoryOwner(fakeDb()), "firestore");
  } finally {
    if (previous === undefined) delete process.env.GIFT_STORY_OWNER_OVERRIDE;
    else process.env.GIFT_STORY_OWNER_OVERRIDE = previous;
  }
});

test("concurrent Gift Story effects execute once and replay returns the recorded result", async () => {
  const db = fakeDb();
  let executions = 0;
  const run = () => runGiftStoryEffect(db, {
    giftId: "gift-1",
    deliveryId: "delivery-1",
    effectId: "sender_story_email",
    source: "cloud_run",
    execute: async () => {
      executions += 1;
      return {queueId: "gift_story_gift-1_sender"};
    },
  });
  const results = await Promise.all(Array.from({length: 20}, run));
  assert.equal(executions, 1);
  assert.equal(results.filter((result) => result.status === "completed").length, 1);
  assert.equal(results.filter((result) => result.status === "duplicate").length, 19);
  const replay = await run();
  assert.deepEqual(replay, {
    status: "duplicate",
    effectId: "sender_story_email",
    result: {queueId: "gift_story_gift-1_sender"},
  });
  assert.equal(executions, 1);
});

test("a completed effect is repaired only when its durable output is missing", async () => {
  const db = fakeDb();
  let outputExists = false;
  let executions = 0;
  const run = () => runGiftStoryEffect(db, {
    giftId: "gift-2",
    deliveryId: "delivery-2",
    effectId: "recipient_phone_whatsapp",
    source: "firestore",
    verify: async () => outputExists,
    execute: async () => {
      executions += 1;
      outputExists = true;
    },
  });
  await run();
  assert.equal(executions, 1);
  outputExists = false;
  await run();
  assert.equal(executions, 2);
});
