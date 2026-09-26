"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {once} = require("node:events");
const {DocumentEventData} = require("./rider-policy-firestore-event");
const {fixtureDb, isFixtureDeliveryId} = require("./gift-story-fixture-db");
const {createServer, decodeEventarcPayload, deliveryIdFromName, claimId, processOnce} = require("./cloud-run-notification-events");
const {processDeliveryCreatedOnce} = require("./platform-notifications");

const EVENT_TYPE = "google.cloud.firestore.document.v1.created";

function firestorePayload(deliveryId = "eventarc-delivery-1") {
  return DocumentEventData.encode({
    value: {
      name: `projects/circum-2797c/databases/(default)/documents/deliveryRequests/${deliveryId}`,
      fields: {
        requestId: {stringValue: deliveryId},
        senderId: {stringValue: "test-eventarc-sender"},
        matchingRules: {mapValue: {fields: {requiresTwoPerson: {booleanValue: true}}}},
      },
    },
  }).finish();
}

function pubsubPushBody(payload) {
  return Buffer.from(JSON.stringify({
    message: {
      data: Buffer.from(payload).toString("base64"),
      messageId: "eventarc-message-1",
      attributes: {"ce-type": EVENT_TYPE},
    },
    subscription: "projects/circum-2797c/subscriptions/eventarc-test",
  }));
}

test("extracts only deliveryRequests document ids", () => {
  assert.equal(deliveryIdFromName("projects/p/databases/(default)/documents/deliveryRequests/d1"), "d1");
  assert.equal(deliveryIdFromName("documents/users/u1"), null);
});

test("business claim is stable per handler and delivery", () => {
  assert.equal(claimId("delivery_created", "d1"), claimId("delivery_created", "d1"));
  assert.notEqual(claimId("delivery_created", "d1"), claimId("gift_delivery_completed", "d1"));
});

test("fixture persistence maps every downstream collection below the isolated event document", () => {
  const ref = (path) => ({path, collection: (name) => collection(`${path}/${name}`)});
  const collection = (path) => ({path, doc: (id) => ref(`${path}/${id}`)});
  const rawDb = {collection, runTransaction: async () => {}, batch: () => ({})};
  assert.equal(isFixtureDeliveryId("__codex_delivery_1"), true);
  assert.equal(isFixtureDeliveryId("customer-delivery-1"), false);
  assert.throws(() => fixtureDb(rawDb, "customer-delivery-1"), /invalid_fixture_delivery_id/);
  const db = fixtureDb(rawDb, "__codex_delivery_1");
  for (const name of ["giftRequests", "giftStoryAccessTokens", "giftStoryCompletionEffects", "eventHandlerClaims",
    "emailQueue", "notifications", "storyNotifications", "whatsappQueue", "imessageQueue", "giftStoryAnalytics",
    "giftStoryCompletionAudit", "users", "chats", "dispatchInspections", "deliveryRequests"]) {
    assert.equal(db.collection(name).path, `giftStoryRuntimeFixtures/__codex_delivery_1/state/${name}/records`);
  }
  assert.equal(db.collection("giftStoryRuntimeFixtures").path, "giftStoryRuntimeFixtures");
});

function claimDb(initial = {}) {
  let data = {...initial};
  let transactionQueue = Promise.resolve();
  const ref = {
    get: async () => ({exists: Object.keys(data).length > 0, data: () => data}),
    set: async (value) => {
      data = {...data, ...value};
    },
  };
  return {
    collection: () => ({doc: () => ref}),
    runTransaction: (callback) => {
      const run = async () => {
        const tx = {
        get: async () => ({exists: Object.keys(data).length > 0, data: () => data}),
        set: (_ref, value) => {
          data = {...data, ...value};
        },
        update: (_ref, value) => {
          for (const [path, valueAtPath] of Object.entries(value)) {
            const keys = path.split(".");
            let target = data;
            while (keys.length > 1) {
              const key = keys.shift();
              target[key] = target[key] || {};
              target = target[key];
            }
            target[keys[0]] = valueAtPath;
          }
        },
        };
        return callback(tx);
      };
      const pending = transactionQueue.then(run);
      transactionQueue = pending.catch(() => {});
      return pending;
    },
    read: () => data,
    write: (value) => {
      data = {...data, ...value};
    },
  };
}

test("expired processing claim can be reclaimed by a retry with a new event id", async () => {
  const db = claimDb({status: "processing", eventId: "crashed-event", leaseExpiresAt: {toMillis: () => Date.now() - 1}});
  let effects = 0;
  const result = await processOnce({db, kind: "delivery_created", eventId: "retry-event", deliveryId: "d1", run: async () => {
    effects += 1;
  }});
  assert.deepEqual(result, {status: "completed"});
  assert.equal(effects, 1);
  assert.equal(db.read().status, "completed");
});

test("active processing claim rejects a competing event id", async () => {
  const db = claimDb({status: "processing", eventId: "active-event", leaseExpiresAt: {toMillis: () => Date.now() + 60000}});
  await assert.rejects(
      processOnce({db, kind: "delivery_created", eventId: "other-event", deliveryId: "d1", run: async () => {}, waitForBusyMs: 0}),
      (error) => error.statusCode === 503,
  );
});

test("retry after the first durable effect skips it and finishes only missing effects", async () => {
  const db = claimDb();
  let first = 0;
  let second = 0;
  await assert.rejects(processOnce({
    db, kind: "delivery_created", eventId: "event-1", deliveryId: "d1",
    run: async ({effects}) => {
      await effects.run("first", async () => {
        first += 1;
      });
      throw new Error("simulated_crash");
    },
  }));
  const result = await processOnce({
    db, kind: "delivery_created", eventId: "event-2", deliveryId: "d1",
    run: async ({effects}) => {
      await effects.run("first", async () => {
        first += 1;
      });
      await effects.run("second", async () => {
        second += 1;
      });
    },
  });
  assert.deepEqual(result, {status: "completed"});
  assert.equal(first, 1);
  assert.equal(second, 1);
});

test("20 concurrent copies produce one logical effect without amplifying retries", async () => {
  const db = claimDb();
  let effects = 0;
  const results = await Promise.allSettled(Array.from({length: 20}, (_, index) => processOnce({
    db, kind: "delivery_created", eventId: `event-${index}`, deliveryId: "d1",
    run: async ({effects: manifest}) => {
      await manifest.run("dispatch_inspection", async () => {
        effects += 1;
      });
    },
  })));
  assert.equal(effects, 1);
  assert.equal(results.filter((result) => result.status === "fulfilled" && result.value.status === "completed").length, 1);
  assert.equal(results.filter((result) => result.status === "fulfilled" && result.value.status === "duplicate").length, 19);
  assert.equal(results.filter((result) => result.status === "rejected").length, 0);
});

test("a stale worker cannot complete after another worker reclaims the lease", async () => {
  const db = claimDb();
  let first = 0;
  let second = 0;
  let releaseFirst;
  const firstPaused = new Promise((resolve) => {
    releaseFirst = resolve;
  });
  let effectCommitted;
  const effectStarted = new Promise((resolve) => {
    effectCommitted = resolve;
  });
  const workerA = processOnce({
    db, kind: "delivery_created", eventId: "event-a", deliveryId: "d1",
    run: async ({effects}) => {
      await effects.run("first", async () => {
        first += 1;
      });
      effectCommitted();
      await firstPaused;
    },
  });
  await effectStarted;
  db.write({leaseExpiresAt: {toMillis: () => Date.now() - 1}});
  const workerB = await processOnce({
    db, kind: "delivery_created", eventId: "event-b", deliveryId: "d1",
    run: async ({effects}) => {
      await effects.run("first", async () => {
        first += 1;
      });
      await effects.run("second", async () => {
        second += 1;
      });
    },
  });
  releaseFirst();
  await assert.rejects(workerA, (error) => error.statusCode === 503);
  assert.deepEqual(workerB, {status: "completed"});
  assert.equal(first, 1);
  assert.equal(second, 1);
  assert.equal(db.read().status, "completed");
});

test("unwraps Eventarc Pub/Sub push bodies before decoding Firestore protobuf", () => {
  const decoded = decodeEventarcPayload(pubsubPushBody(firestorePayload()));
  assert.equal(decoded.documentName, "projects/circum-2797c/databases/(default)/documents/deliveryRequests/eventarc-delivery-1");
  assert.equal(decoded.after.requestId, "eventarc-delivery-1");
  assert.equal(decoded.after.senderId, "test-eventarc-sender");
  assert.equal(decoded.after.matchingRules.requiresTwoPerson, true);
});

test("accepts an Eventarc Pub/Sub request and forwards decoded delivery fields", async () => {
  let received;
  const server = createServer({
    kind: "delivery_created",
    dbFactory: () => ({unused: true}),
    processOnce: async (input) => {
      received = input;
      return {status: "completed"};
    },
  });
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  try {
    const {port} = server.address();
    const response = await fetch(`http://127.0.0.1:${port}/`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "ce-type": EVENT_TYPE,
        "ce-id": "eventarc-push-1",
      },
      body: pubsubPushBody(firestorePayload("eventarc-delivery-2")),
    });
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {ok: true, status: "completed"});
    assert.equal(received.deliveryId, "eventarc-delivery-2");
    assert.equal(received.after.matchingRules.requiresTwoPerson, true);
  } finally {
    server.close();
    await once(server, "close");
  }
});

test("rejects malformed Eventarc payloads as client errors", async () => {
  const server = createServer({
    kind: "gift_delivery_completed",
    dbFactory: () => ({unused: true}),
    processOnce: async () => {
      throw new Error("malformed payload must not reach the handler");
    },
  });
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  try {
    const response = await fetch(`http://127.0.0.1:${server.address().port}/`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "ce-type": "google.cloud.firestore.document.v1.updated",
        "ce-id": "malformed-event",
      },
      body: "{}",
    });
    assert.equal(response.status, 400);
    assert.deepEqual(await response.json(), {error: "handler_failed"});
  } finally {
    server.close();
    await once(server, "close");
  }
});

test("Gift completion Eventarc route accepts only the delivery update and preserves both states", async () => {
  let received;
  let claims = 0;
  const server = createServer({kind: "gift_delivery_completed", dbFactory: () => ({unused: true}),
    processOnce: async (input) => {
      claims++;
      received = input;
      return {status: "completed"};
    }});
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  try {
    const send = async (oldStatus, newStatus, serviceType = "gifts") => {
      const link = serviceType === "gifts" ? {giftRequestId: {stringValue: "gift-1"}} : {};
      const payload = DocumentEventData.encode({
      value: {name: "projects/circum-2797c/databases/(default)/documents/deliveryRequests/gift-delivery-1",
        fields: {status: {stringValue: newStatus}, ...link, serviceType: {stringValue: serviceType}}},
      oldValue: {name: "projects/circum-2797c/databases/(default)/documents/deliveryRequests/gift-delivery-1",
        fields: {status: {stringValue: oldStatus}, ...link, serviceType: {stringValue: serviceType}}},
      }).finish();
      return fetch(`http://127.0.0.1:${server.address().port}/`, {method: "POST",
      headers: {"content-type": "application/json", "ce-type": "google.cloud.firestore.document.v1.updated",
        "ce-id": `gift-event-${oldStatus}-${newStatus}-${serviceType}`}, body: pubsubPushBody(payload)});
    };
    const transit = await send("assigned", "in_transit");
    assert.equal(transit.status, 200);
    assert.equal((await transit.json()).status, "ignored");
    assert.equal(claims, 0);
    const otherService = await send("in_transit", "completed", "standard");
    assert.equal(otherService.status, 200);
    assert.equal((await otherService.json()).status, "ignored");
    assert.equal(claims, 0);
    const response = await send("in_transit", "completed");
    assert.equal(response.status, 200);
    assert.equal(claims, 1);
    assert.equal(received.kind, "gift_delivery_completed");
    assert.equal(received.deliveryId, "gift-delivery-1");
    assert.equal(received.before.status, "in_transit");
    assert.equal(received.after.status, "completed");
    assert.equal(received.after.giftRequestId, "gift-1");
  } finally {
    server.close();
    await once(server, "close");
  }
});

test("Gift completion fixture collection is bounded and does not change production routing", async () => {
  const previous = process.env.GIFT_STORY_EVENT_COLLECTION_OVERRIDE;
  process.env.GIFT_STORY_EVENT_COLLECTION_OVERRIDE = "giftStoryRuntimeFixtures";
  let received;
  const fixtureRawDb = {collection: () => ({doc: () => ({})}), runTransaction: async () => {}, batch: () => ({})};
  const server = createServer({kind: "gift_delivery_completed", dbFactory: () => fixtureRawDb,
    processOnce: async (input) => {
      received = input;
      return {status: "completed"};
    }});
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  try {
    const name = "projects/circum-2797c/databases/(default)/documents/giftStoryRuntimeFixtures/__codex_fixture_1";
    const payload = DocumentEventData.encode({
      value: {name, fields: {status: {stringValue: "completed"}, serviceType: {stringValue: "GIFTS"}}},
      oldValue: {name, fields: {status: {stringValue: "in_transit"}, serviceType: {stringValue: "GIFTS"}}},
    }).finish();
    const response = await fetch(`http://127.0.0.1:${server.address().port}/`, {
      method: "POST",
      headers: {"content-type": "application/json", "ce-type": "google.cloud.firestore.document.v1.updated", "ce-id": "fixture-collection-event"},
      body: pubsubPushBody(payload),
    });
    assert.equal(response.status, 200);
    assert.equal(received.deliveryId, "__codex_fixture_1");
    assert.equal(received.db.fixtureMode, true);
    assert.equal(received.after.status, "completed");
  } finally {
    server.close();
    await once(server, "close");
    if (previous === undefined) delete process.env.GIFT_STORY_EVENT_COLLECTION_OVERRIDE;
    else process.env.GIFT_STORY_EVENT_COLLECTION_OVERRIDE = previous;
  }
});

test("Gen 1 delivery create path delegates to the Cloud Run durable claim", async () => {
  let received;
  let effects = 0;
  const snapshot = {id: "delivery-1", data: () => ({status: "requested"})};
  const result = await processDeliveryCreatedOnce(snapshot, "gen1-event-1", {
    db: {unused: true},
    processOnce: async (input) => {
      received = input;
      await input.run();
      return {status: "completed"};
    },
    run: async () => {
      effects += 1;
    },
  });
  assert.deepEqual(result, {status: "completed"});
  assert.equal(effects, 1);
  assert.equal(received.kind, "delivery_created");
  assert.equal(received.eventId, "gen1-event-1");
  assert.equal(received.deliveryId, "delivery-1");
});
