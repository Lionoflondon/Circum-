"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {normalizeEmail, normalizeCategories, sha256, CATEGORIES} = require("./newsletter")._private;

test("newsletter normalizes email and creates deterministic identifiers", () => {
  assert.equal(normalizeEmail("  HELLO@Example.COM "), "hello@example.com");
  assert.equal(sha256("hello@example.com"), sha256("hello@example.com"));
});

test("newsletter rejects malformed email and optional categories are never implicit", () => {
  assert.throws(() => normalizeEmail("not-an-email"));
  assert.deepEqual(normalizeCategories(null), ["circum_updates"]);
  assert.deepEqual(normalizeCategories([CATEGORIES[1]]), [CATEGORIES[1]]);
  assert.throws(() => normalizeCategories(["unknown"]));
});

test("newsletter module is callable-only with no Firestore trigger export", () => {
  const module = require("./newsletter");
  for (const key of ["submitNewsletterSignup", "getNewsletterPreferences", "updateNewsletterPreferences", "unsubscribeNewsletter"]) {
    assert.ok(module[key], `${key} is exported`);
  }
  assert.equal(Object.keys(module).some((key) => key.startsWith("onNewsletter")), false);
});
