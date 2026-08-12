/* eslint-disable max-len */
"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const test = require("node:test");

test("Business monthly reporting aggregate has its production index", () => {
  const config = JSON.parse(fs.readFileSync("../../firestore.indexes.json", "utf8"));
  const required = ["businessId", "createdAt", "durationMinutes", "paidAmount", "__name__"];
  const present = config.indexes.some((index) =>
    index.collectionGroup === "deliveryRequests" &&
    required.every((field, position) => index.fields[position] && index.fields[position].fieldPath === field));

  assert.equal(present, true, "Business reporting aggregate index must ship with every backend release");
});
