/* eslint-disable max-len, require-jsdoc */
"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {fixtureDb} = require("./gift-story-fixture-db");
const {handlers, processOnce} = require("./cloud-run-notification-events");

function memoryDb(initial = {}) {
  const values = new Map(Object.entries(initial));
  let transactionQueue = Promise.resolve();
  const ref = (path) => ({
    id: path.split("/").at(-1),
    path,
    collection: (name) => collection(`${path}/${name}`),
    get: async () => ({id: path.split("/").at(-1), exists: values.has(path), ref: ref(path), data: () => values.get(path)}),
    set: async (value, options = {}) => values.set(path, options.merge ? {...(values.get(path) || {}), ...value} : value),
    create: async (value) => {
      if (values.has(path)) throw Object.assign(new Error("Already exists"), {code: 6});
      values.set(path, value);
    },
  });
  const collection = (path) => ({doc: (id) => ref(`${path}/${id}`)});
  const db = {
    collection,
    runTransaction: (callback) => {
      const run = async () => {
        const writes = [];
        const tx = {
          get: (document) => document.get(),
          set: (document, value, options) => writes.push({document, value, options}),
          update: (document, value) => writes.push({document, value, options: {merge: true}}),
        };
        const result = await callback(tx);
        for (const {document, value, options} of writes) await document.set(value, options);
        return result;
      };
      const pending = transactionQueue.then(run);
      transactionQueue = pending.catch(() => {});
      return pending;
    },
    batch: () => {
      const writes = [];
      return {set: (document, value, options) => writes.push({document, value, options}),
        commit: async () => {
          for (const {document, value, options} of writes) await document.set(value, options);
        }};
    },
  };
  return {db, values};
}

test("fixture Gift completion executes Story effects only below its isolated document", async () => {
  const previous = process.env.GIFT_STORY_OWNER_OVERRIDE;
  process.env.GIFT_STORY_OWNER_OVERRIDE = "cloud_run";
  const deliveryId = "__codex_delivery_isolation";
  const giftId = "__codex_gift_isolation";
  const prefix = `giftStoryRuntimeFixtures/${deliveryId}`;
  const giftPath = `${prefix}/state/giftRequests/records/${giftId}`;
  const {db: rawDb, values} = memoryDb({[giftPath]: {
    senderId: "__codex_sender_isolation",
    senderEmail: "sender@example.invalid",
    recipientEmail: "recipient@example.invalid",
    recipientPhone: "+447700900123",
    recipientName: "Fixture Recipient",
    status: "approved",
  }});
  const db = fixtureDb(rawDb, deliveryId);
  try {
    const runOnce = (eventId) => processOnce({db, kind: "gift_delivery_completed", eventId, deliveryId,
      before: {status: "in_transit"}, after: {status: "completed", serviceType: "gifts", giftRequestId: giftId},
      run: handlers.gift_delivery_completed.run});
    const results = await Promise.all(Array.from({length: 20}, (_, index) => runOnce(`fixture-event-${index}`)));
    assert.equal(results.filter((result) => result.status === "completed").length, 1);
    assert.equal(results.filter((result) => result.status === "duplicate").length, 19);
    assert.equal((await runOnce("delayed-retry")).status, "duplicate");
    assert.equal(values.get(giftPath).giftStoryStatus, "unlocked");
    assert.equal([...values.keys()].filter((path) => path.includes("/state/eventHandlerClaims/records/")).length, 1);
    assert.equal([...values.keys()].filter((path) => path.includes("/state/giftStoryCompletionEffects/records/")).length, 7);
    assert.equal([...values.keys()].filter((path) => path.includes("/state/emailQueue/records/")).length, 3);
    assert.equal([...values.keys()].filter((path) => path.includes("/state/giftStoryAccessTokens/records/")).length, 2);
    assert.equal([...values.keys()].filter((path) => path.includes("/state/notifications/records/")).length, 1);
    assert.equal([...values.keys()].filter((path) => path.includes("/state/storyNotifications/records/")).length, 4);
    assert.equal([...values.keys()].filter((path) => path.includes("/state/whatsappQueue/records/")).length, 1);
    assert.equal([...values.keys()].filter((path) => path.includes("/state/giftStoryCompletionAudit/records/")).length, 1);
    assert.equal([...values.keys()].filter((path) => path.includes("/state/giftStoryAnalytics/records/")).length, 1);
    const senderNotificationPath = [...values.keys()].find((path) => path.includes("/state/notifications/records/"));
    assert.equal(values.get(senderNotificationPath).pushDeliveryStatus, "skipped");
    assert.ok([...values.keys()].every((path) => path.startsWith(`${prefix}/`) || path === prefix));
  } finally {
    if (previous === undefined) delete process.env.GIFT_STORY_OWNER_OVERRIDE;
    else process.env.GIFT_STORY_OWNER_OVERRIDE = previous;
  }
});
