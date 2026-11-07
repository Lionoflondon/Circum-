"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {activeRevisionName, validateRevision} = require("./verify_roth_live_release_owners.cjs");

const certifiedSha = "f1275c63ab3db56f220ee4f557582db44e257301";
function service(name) {
  return {status: {conditions: [{type: "Ready", status: "True"}], traffic: [{revisionName: name, percent: 100}]}};
}
function revision(values) {
  return {
    status: {conditions: [{type: "Ready", status: "True"}]},
    spec: {containers: [{image: "us-central1-docker.pkg.dev/project/service@sha256:abc123", env: Object.entries(values).map(([name, value]) => ({name, value}))}]},
  };
}

test("public ROTH release requires one Ready untagged 100 percent revision per owner", () => {
  assert.equal(activeRevisionName(service("stripe-ready"), "circum-stripe-webhook-live"), "stripe-ready");
  for (const value of [
    {status: {conditions: [{type: "Ready", status: "False"}], traffic: [{revisionName: "x", percent: 100}]}},
    {status: {conditions: [{type: "Ready", status: "True"}], traffic: [{revisionName: "x", percent: 90}]}},
    {status: {conditions: [{type: "Ready", status: "True"}], traffic: [{revisionName: "x", percent: 100, tag: "candidate"}]}},
  ]) assert.throws(() => activeRevisionName(value, "circum-stripe-webhook-live"));
});

test("both LIVE payment owners must retain immutable images and the certified ROTH guard", () => {
  const stripe = revision({STRIPE_MODE: "live", CIRCUM_SOURCE_SHA: "f0c24ebc763552f832c26838f14f4c679aa654d7", CIRCUM_ROTH_GUARD_SHA: certifiedSha});
  const email = revision({CIRCUM_SOURCE_SHA: "b4b21042498793b3d2515adf7b22444ff1b1c60d", CIRCUM_RECOVERY_BASE_SHA: "b4b21042498793b3d2515adf7b22444ff1b1c60d", CIRCUM_PASSWORD_RECOVERY_SHA: "8b4a31365fe090b52e099dd2ed869e87db384699", CIRCUM_ROTH_GUARD_SHA: certifiedSha});
  assert.equal(validateRevision(stripe, "circum-stripe-webhook-live", certifiedSha), true);
  assert.equal(validateRevision(email, "circum-transactional-email", certifiedSha), true);
  for (const patch of [
    (value) => { value.spec.containers[0].image = "mutable:latest"; },
    (value) => { value.spec.containers[0].env.find((entry) => entry.name === "CIRCUM_ROTH_GUARD_SHA").value = "a".repeat(40); },
    (value) => { value.spec.containers[0].env.find((entry) => entry.name === "STRIPE_MODE").value = "test"; },
  ]) {
    const bad = structuredClone(stripe); patch(bad);
    assert.throws(() => validateRevision(bad, "circum-stripe-webhook-live", certifiedSha));
  }
  assert.throws(() => validateRevision(email, "circum-transactional-email", "a".repeat(40)));
});
