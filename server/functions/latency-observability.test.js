const {test} = require("node:test");
const assert = require("node:assert/strict");
const {timing, start} = require("./latency-observability");

test("latency events contain no sensitive fields", () => {
  const original = console.info;
  const entries = [];
  console.info = (_, entry) => entries.push(entry);
  try {
    const complete = start("QUOTE", {correlationId: "opaque-delivery-id", workloadCount: 3});
    complete({success: true});
    timing("DISPATCH_START", {correlationId: "opaque-request-id", riderCount: 3});
  } finally {
    console.info = original;
  }
  const serialized = JSON.stringify(entries);
  assert.doesNotMatch(serialized, /email|phone|address|token|secret|recipient|payment|latitude|longitude|documentUrl/i);
  assert.equal(entries.every((entry) => entry.stage && entry.at), true);
});

test("telemetry failure is fail-open", () => {
  const original = console.info;
  console.info = () => {
    throw new Error("logging unavailable");
  };
  assert.doesNotThrow(() => timing("QUOTE_START", {correlationId: "opaque"}));
  console.info = original;
});
