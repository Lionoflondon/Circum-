"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {becameCompleted} = require("./referrals")._private;

test("referrals qualify only on explicit terminal completion states", () => {
  assert.equal(becameCompleted({status: "submitted_for_review"}, {status: "active"}), false);
  assert.equal(becameCompleted({status: "paid_waiting_for_match"}, {status: "active"}), false);
  assert.equal(becameCompleted({status: "assigned"}, {status: "delivered"}), true);
  assert.equal(becameCompleted({status: "collected"}, {status: "completed"}), true);
  assert.equal(becameCompleted({status: "delivered"}, {status: "delivered"}), false);
});

test("referrals do not broaden completion states through the shared detector", () => {
  assert.equal(becameCompleted({giftStatus: "submitted_for_review"}, {giftStatus: "active"}), false);
  assert.equal(becameCompleted({status: "scheduled"}, {status: "active"}), false);
  assert.equal(becameCompleted({status: "scheduled"}, {status: "completed"}), true);
});
