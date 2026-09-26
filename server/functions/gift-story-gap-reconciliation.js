/* eslint-disable max-len, require-jsdoc */
"use strict";

const {FieldPath, Timestamp} = require("firebase-admin/firestore");
const {getGiftStoryOwner} = require("./gift-story-completion-core");
const {isGiftDelivery, isComplete, unlockGiftStory} = require("./gift-story-automation");

const MAX_WINDOW_MS = 24 * 60 * 60 * 1000;
const MAX_PAGE_SIZE = 50;
const MAX_RECORDS = 200;
const text = (value) => `${value || ""}`.trim();

function windowBounds(start, end) {
  if (![start, end].every((value) => typeof value === "string" && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z$/.test(value))) {
    throw new Error("reconciliation_requires_utc_bounds");
  }
  const startMs = Date.parse(start);
  const endMs = Date.parse(end);
  if (!Number.isFinite(startMs) || !Number.isFinite(endMs) || startMs >= endMs || endMs - startMs > MAX_WINDOW_MS) {
    throw new Error("reconciliation_window_out_of_bounds");
  }
  return {startMs, endMs, startAt: Timestamp.fromMillis(startMs), endAt: Timestamp.fromMillis(endMs)};
}

function boundedInteger(value, maximum, label) {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 1 || parsed > maximum) throw new Error(`invalid_${label}`);
  return parsed;
}

function cursorValue(token, bounds) {
  if (!token) return null;
  if (typeof token !== "string" || token.length > 600) throw new Error("invalid_reconciliation_cursor");
  let parsed;
  try {
    parsed = JSON.parse(Buffer.from(token, "base64url").toString("utf8"));
  } catch (_) {
    throw new Error("invalid_reconciliation_cursor");
  }
  if (parsed.startMs !== bounds.startMs || parsed.endMs !== bounds.endMs ||
      !/^[A-Za-z0-9_-]{1,200}$/.test(text(parsed.id)) ||
      !Number.isInteger(parsed.seconds) || !Number.isInteger(parsed.nanoseconds) ||
      parsed.nanoseconds < 0 || parsed.nanoseconds >= 1e9) {
    throw new Error("invalid_reconciliation_cursor");
  }
  const at = new Timestamp(parsed.seconds, parsed.nanoseconds);
  if (at.toMillis() < bounds.startMs || at.toMillis() > bounds.endMs) throw new Error("invalid_reconciliation_cursor");
  return {at, id: parsed.id};
}

function nextCursor(snapshot, bounds) {
  const at = snapshot.get("completedAt");
  if (!at || !Number.isInteger(at.seconds) || !Number.isInteger(at.nanoseconds)) {
    throw new Error("malformed_completion_timestamp");
  }
  return encodeCursor({at, id: snapshot.id}, bounds);
}

function encodeCursor(position, bounds) {
  if (!position) return null;
  return Buffer.from(JSON.stringify({startMs: bounds.startMs, endMs: bounds.endMs,
    seconds: position.at.seconds, nanoseconds: position.at.nanoseconds, id: position.id})).toString("base64url");
}

async function linkedGift(db, deliveryId, delivery) {
  const directId = text(delivery.giftOrderId || delivery.giftRequestId);
  let snapshot;
  if (directId) {
    snapshot = await db.collection("giftRequests").doc(directId).get();
  } else {
    const matches = await db.collection("giftRequests").where("deliveryId", "==", deliveryId).limit(1).get();
    snapshot = matches.docs[0];
  }
  if (!snapshot || !snapshot.exists) return null;
  const gift = snapshot.data() || {};
  if (text(gift.deliveryId) && text(gift.deliveryId) !== deliveryId) return null;
  if (directId && snapshot.id !== directId) return null;
  return snapshot;
}

async function reconcileGiftStoryWindow({db, start, end, pageSize = 25, maxRecords = 100, cursor = "", apply = false,
  runCompletion = unlockGiftStory, ownerReader = getGiftStoryOwner}) {
  if (!db) throw new Error("reconciliation_requires_db");
  const bounds = windowBounds(start, end);
  const pageLimit = boundedInteger(pageSize, MAX_PAGE_SIZE, "page_size");
  const workLimit = boundedInteger(maxRecords, MAX_RECORDS, "max_records");
  let position = cursorValue(cursor, bounds);
  if (apply && await ownerReader(db) !== "cloud_run") throw new Error("reconciliation_requires_cloud_run_owner");
  const counts = {candidates: 0, processed: 0, alreadyClaimed: 0, ignored: 0, errors: 0};
  let examined = 0;
  let more = true;
  while (examined < workLimit && more) {
    const limit = Math.min(pageLimit, workLimit - examined);
    let query = db.collection("deliveryRequests")
        .where("completedAt", ">=", bounds.startAt)
        .where("completedAt", "<=", bounds.endAt)
        .orderBy("completedAt")
        .orderBy(FieldPath.documentId())
        .limit(limit);
    if (position) query = query.startAfter(position.at, position.id);
    const page = await query.get();
    if (page.docs.length < limit) more = false;
    for (const snapshot of page.docs) {
      const delivery = snapshot.data() || {};
      if (!isGiftDelivery(delivery) || !isComplete(delivery.status)) {
        counts.ignored++;
      } else {
        const gift = await linkedGift(db, snapshot.id, delivery);
        if (!gift) {
          counts.errors++;
          return {...counts, examined, nextCursor: encodeCursor(position, bounds)};
        } else {
          counts.candidates++;
          if (apply) {
            try {
              const result = await runCompletion(db, gift, snapshot.id, {source: "reconciliation"});
              if (result.effectiveEffects > 0) counts.processed++;
              else counts.alreadyClaimed++;
            } catch (_) {
              counts.errors++;
              return {...counts, examined, nextCursor: encodeCursor(position, bounds)};
            }
          }
        }
      }
      examined++;
      position = cursorValue(nextCursor(snapshot, bounds), bounds);
    }
    if (!page.docs.length) break;
  }
  return {...counts, examined, nextCursor: more ? encodeCursor(position, bounds) : null};
}

module.exports = {windowBounds, cursorValue, nextCursor, encodeCursor, linkedGift, reconcileGiftStoryWindow,
  MAX_WINDOW_MS, MAX_PAGE_SIZE, MAX_RECORDS};
