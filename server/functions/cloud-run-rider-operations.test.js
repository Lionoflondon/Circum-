const assert = require("node:assert/strict");
const test = require("node:test");
const {createHandlers, routeName} = require("./cloud-run-rider-operations");

test("every lazy operation adapter resolves its real export and rejects missing authentication", async () => {
  for (const [name, handler] of Object.entries(createHandlers())) {
    await assert.rejects(() => handler({}, {auth: null}), (error) => {
      assert.equal(error.code, "unauthenticated", `${name}: ${error.stack}`);
      return true;
    });
  }
});
test("operation allowlist includes authoritative push registration and excludes arbitrary routes", () => {
  assert.equal(routeName("/updateRiderPushToken"), "updateRiderPushToken");
  assert.equal(routeName("/unknown"), null);
});

test("HTTP adapter requires both verified credentials and preserves exact job/token data", async () => {
  const {createServer} = require("./cloud-run-rider-operations");
  const observed = [];
  const server = createServer({dependenciesFactory: () => ({
    verifyIdToken: async (token) => {
      assert.equal(token, "auth");
      return {uid: "rider-1", email_verified: true};
    },
    verifyAppCheck: async (token) => {
      assert.equal(token, "appcheck");
      return {appId: "approved-app"};
    },
    handlers: {updateRiderPushToken: async (data, context) => {
      observed.push({data, context});
      return {ok: true};
    }},
  })});
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const url = `http://127.0.0.1:${server.address().port}/updateRiderPushToken`;
  try {
    const post = (headers, body = "{\"data\":{\"fcmToken\":\"exact-device\"}}") => fetch(url, {
      method: "POST", headers: {"content-type": "application/json", ...headers}, body,
    });
    assert.equal((await post({})).status, 401);
    assert.equal((await post({authorization: "Bearer auth"})).status, 400);
    const headers = {authorization: "Bearer auth", "x-firebase-appcheck": "appcheck"};
    assert.equal((await post(headers, "{")).status, 400);
    const response = await post(headers);
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {result: {ok: true}});
    assert.equal(observed.length, 1);
    assert.deepEqual(observed[0].data, {fcmToken: "exact-device"});
    assert.equal(observed[0].context.auth.uid, "rider-1");
    assert.equal(observed[0].context.app.appId, "approved-app");
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});
