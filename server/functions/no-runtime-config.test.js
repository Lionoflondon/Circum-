/* eslint-disable max-len */
"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

test("production Functions never read retired functions.config()", () => {
  const directory = __dirname;
  const offenders = fs.readdirSync(directory)
      .filter((name) => name.endsWith(".js") && !name.endsWith(".test.js"))
      .filter((name) => /functions\s*\.\s*config\s*\(/.test(
          fs.readFileSync(path.join(directory, name), "utf8"),
      ));

  assert.deepEqual(offenders, []);
});
