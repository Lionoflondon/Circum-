/* eslint-disable max-len, require-jsdoc */
"use strict";
const {GoogleAuth} = require("google-auth-library");
const DESTINATION = "https://circum-qa-special-flow-j2b7cicfwq-uc.a.run.app";
const WORKERS = new Set(["expireQaLifecycleFixtures", "expireQaSpecialFlowFixtures"]);
async function certify(input, getClient = () => new GoogleAuth().getIdTokenClient(DESTINATION)) {
  if (!WORKERS.has(input.worker) || !/^__codex_[A-Za-z0-9_-]{1,100}$/.test(input.fixtureId || "")) throw Object.assign(new Error("invalid_test_certification"), {statusCode: 400});
  const client = await getClient();
  const result = await client.request({url: `${DESTINATION}/recovery/${input.worker}/fixture`, method: "POST", data: {fixtureId: input.fixtureId}, timeout: 55000});
  return result.data;
}
function handle(req, res) {
  if (new URL(req.url, "http://localhost").pathname !== "/qa-cleanup-certification") return false;
  const send = (status, body) => {
res.writeHead(status, {"Content-Type": "application/json", "Cache-Control": "no-store"}); res.end(JSON.stringify(body));
};
  if (req.method !== "POST") {
send(405, {error: "method_not_allowed"}); return true;
}
  let size = 0; const chunks = [];
  req.on("data", (chunk) => {
size += chunk.length; if (size <= 16384) chunks.push(chunk);
});
  req.on("end", async () => {
    try {
if (size > 16384) throw Object.assign(new Error("body_too_large"), {statusCode: 413}); send(200, await certify(JSON.parse(Buffer.concat(chunks).toString("utf8"))));
} catch (error) {
send(error.statusCode || 503, {error: error.statusCode ? error.message : "test_certification_failed"});
}
  });
  return true;
}
module.exports = {handle, certify};
