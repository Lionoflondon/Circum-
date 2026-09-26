/* eslint-disable require-jsdoc */
"use strict";

const {initializeApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {reconcileGiftStoryWindow} = require("./gift-story-gap-reconciliation");

async function main(env = process.env) {
  const apply = env.GIFT_STORY_RECONCILE_APPLY === "true";
  if (apply && env.GIFT_STORY_RECONCILE_CONFIRM !== "gift-story-no-owner-gap") {
    throw new Error("reconciliation_apply_confirmation_required");
  }
  initializeApp();
  const db = getFirestore();
  db.settings({ignoreUndefinedProperties: true});
  const result = await reconcileGiftStoryWindow({db,
    start: env.GIFT_STORY_RECONCILE_START,
    end: env.GIFT_STORY_RECONCILE_END,
    pageSize: Number(env.GIFT_STORY_RECONCILE_PAGE_SIZE || 25),
    maxRecords: Number(env.GIFT_STORY_RECONCILE_MAX_RECORDS || 100),
    cursor: env.GIFT_STORY_RECONCILE_CURSOR || "",
    apply,
  });
  process.stdout.write(`${JSON.stringify({mode: apply ? "apply" : "dry_run", ...result})}\n`);
  if (result.errors) {
    process.exitCode = 1;
  }
}

if (require.main === module) {
  main().catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  });
}

module.exports = {main};
