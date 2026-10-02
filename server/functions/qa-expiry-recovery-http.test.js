/* eslint-disable max-len, require-jsdoc */
"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {authorize} = require("./qa-expiry-recovery-http");
test("QA scheduled cleanup requires a verified Google identity from the existing scheduler authorities", async () => {
  const good = {email: "circum-payment-scheduler@circum-2797c.iam.gserviceaccount.com", email_verified: true};
  const verify = (payload) => ({verifyIdToken: async (options) => {
    assert.equal(options.audience, "https://circum-qa-special-flow-j2b7cicfwq-uc.a.run.app"); return {getPayload: () => payload};
  }});
  await authorize({headers: {authorization: "Bearer opaque"}}, verify(good));
  await assert.rejects(authorize({headers: {}}, verify(good)), {statusCode: 401});
  await assert.rejects(authorize({headers: {authorization: "Bearer opaque"}}, verify({...good, email_verified: false})), {statusCode: 403});
  await assert.rejects(authorize({headers: {authorization: "Bearer opaque"}}, verify({...good, email: "unrelated@circum-2797c.iam.gserviceaccount.com"})), {statusCode: 403});
  await assert.rejects(authorize({headers: {authorization: "Bearer opaque"}}, {verifyIdToken: async () => {
throw new Error("bad_signature");
}}), {statusCode: 401});
});
