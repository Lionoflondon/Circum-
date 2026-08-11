/* eslint-disable max-len, require-jsdoc */
"use strict";

const functions = require("firebase-functions/v1");
const {FieldPath, FieldValue, getFirestore} = require("firebase-admin/firestore");
const {requireAdmin} = require("./admin-auth");
const {_normalizeUsername: normalizeUsername} = require("./username-authority");

const SOURCES = [
  ["users", "username"], ["users", "handle"], ["users", "senderUsername"],
  ["riders", "username"], ["riders", "handle"], ["riders", "riderHandle"],
  ["riderProfiles", "username"], ["riderProfiles", "handle"],
  ["riderProfiles", "riderHandle"],
];
const STATUSES = new Set([
  "MIGRATED", "ALREADY_CANONICAL", "COLLISION_REVIEW_REQUIRED",
  "INVALID_LEGACY_HANDLE", "MISSING_HANDLE",
]);

function candidateRowsForUser(userId, documents) {
  const rows = [];
  for (const [collection, field] of SOURCES) {
    const data = documents[collection] || {};
    if (data[field] !== undefined && data[field] !== null && String(data[field]).trim()) {
      rows.push({uid: userId, source: `${collection}.${field}`, raw: String(data[field])});
    }
  }
  if (rows.length === 0) rows.push({uid: userId, source: "", raw: "", status: "MISSING_HANDLE"});
  return rows;
}

function planLegacyRows(rows, registry = new Map()) {
  const byHandle = new Map();
  const byUid = new Map();
  const results = new Map();
  for (const row of rows) {
    if (row.status === "MISSING_HANDLE") {
      results.set(row.uid, {uid: row.uid, status: "MISSING_HANDLE", sources: []});
      continue;
    }
    try {
      const normalized = normalizeUsername(row.raw).normalized;
      const item = {uid: row.uid, normalized, source: row.source};
      if (!byHandle.has(normalized)) byHandle.set(normalized, []);
      byHandle.get(normalized).push(item);
      if (!byUid.has(row.uid)) byUid.set(row.uid, []);
      byUid.get(row.uid).push(item);
    } catch (_error) {
      row.status = "INVALID_LEGACY_HANDLE";
    }
  }
  for (const [uid, candidates] of byUid) {
    const handles = [...new Set(candidates.map((item) => item.normalized))];
    const sources = candidates.map((item) => item.source);
    if (handles.length !== 1) {
      results.set(uid, {uid, status: "COLLISION_REVIEW_REQUIRED", normalizedHandles: handles, sources});
      continue;
    }
    const normalized = handles[0];
    const owners = new Set((byHandle.get(normalized) || []).map((item) => item.uid));
    const existing = registry.get(normalized);
    if (owners.size > 1 || (existing && existing.uid !== uid)) {
      results.set(uid, {uid, status: "COLLISION_REVIEW_REQUIRED", normalizedHandle: normalized, sources});
    } else if (existing && existing.uid === uid) {
      results.set(uid, {uid, status: "ALREADY_CANONICAL", normalizedHandle: normalized, sources});
    } else {
      results.set(uid, {uid, status: "MIGRATED", normalizedHandle: normalized, sources});
    }
  }
  for (const row of rows) {
    if (row.status === "INVALID_LEGACY_HANDLE") {
      results.set(row.uid, {uid: row.uid, status: "INVALID_LEGACY_HANDLE", sources: [row.source]});
    }
  }
  return results;
}

async function loadUserPage(db, cursor, pageSize) {
  const positions = cursor && typeof cursor === "object" ? cursor : {};
  const collections = ["users", "riders", "riderProfiles"];
  const snapshots = await Promise.all(collections.map(async (collection) => {
    let query = db.collection(collection).orderBy(FieldPath.documentId()).limit(pageSize);
    if (positions[collection]) query = query.startAfter(positions[collection]);
    return query.get();
  }));
  const documents = new Map();
  snapshots.forEach((snapshot, index) => snapshot.docs.forEach((document) => {
    if (!documents.has(document.id)) documents.set(document.id, {});
    documents.get(document.id)[collections[index]] = document.data();
  }));
  const rows = [];
  for (const [uid, values] of documents) rows.push(...candidateRowsForUser(uid, values));
  const nextCursor = {};
  snapshots.forEach((snapshot, index) => {
    const last = snapshot.docs[snapshot.docs.length - 1];
    if (last) nextCursor[collections[index]] = last.id;
  });
  return {rows, docs: [...documents.keys()], nextCursor, done: snapshots.every((snapshot) => snapshot.docs.length < pageSize)};
}

async function migratePage({db, cursor, pageSize = 50, dryRun = true, actor = "dry-run"}) {
  const boundedSize = Math.max(1, Math.min(100, Number(pageSize) || 50));
  const page = await loadUserPage(db, cursor, boundedSize);
  const registry = new Map();
  for (const plan of page.rows) {
    let normalized;
    try {
 normalized = normalizeUsername(plan.raw).normalized;
} catch (_error) {
 continue;
}
    const snap = await db.collection("usernames").doc(normalized).get();
    if (snap && snap.exists) registry.set(snap.id, snap.data());
  }
  const plans = [...planLegacyRows(page.rows, registry).values()];
  const counts = {
    scanned: page.docs.length, accountsWithHandles: new Set(page.rows.map((r) => r.uid)).size,
    MIGRATED: 0, ALREADY_CANONICAL: 0, COLLISION_REVIEW_REQUIRED: 0,
    INVALID_LEGACY_HANDLE: 0, MISSING_HANDLE: 0,
  };
  for (const plan of plans) {
    counts[plan.status] += 1;
    if (dryRun || plan.status !== "MIGRATED") continue;
    const registryRef = db.collection("usernames").doc(plan.normalizedHandle);
    const userRef = db.collection("users").doc(plan.uid);
    await db.runTransaction(async (transaction) => {
      const registrySnap = await transaction.get(registryRef);
      if (registrySnap.exists && registrySnap.data().uid !== plan.uid) return;
      if (!registrySnap.exists) {
transaction.create(registryRef, {
        uid: plan.uid, canonicalHandle: plan.normalizedHandle,
        displayHandle: plan.normalizedHandle, status: "active",
        createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
      });
}
      transaction.set(userRef, {
        username: plan.normalizedHandle, usernameMigrationStatus: "migrated",
        usernameMigrationUpdatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      for (const collection of ["riders", "riderProfiles"]) {
        transaction.set(db.collection(collection).doc(plan.uid), {
          username: plan.normalizedHandle,
          usernameMigrationStatus: "migrated",
          usernameMigrationUpdatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
      }
      transaction.set(db.collection("usernameMigrationState").doc(plan.uid), {
        uid: plan.uid, status: plan.status, normalizedHandle: plan.normalizedHandle,
        sourceFields: plan.sources, actor, updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    });
  }
  return {counts, reports: plans.map(({uid, normalizedHandle, sources, status}) =>
    ({uid, normalizedHandle: normalizedHandle || null, sourceFields: sources, status})),
  nextCursor: page.done ? null : page.nextCursor, done: page.done};
}

exports.migrateCircumUsernames = functions.runWith({enforceAppCheck: true}).https.onCall(async (data, context) => {
  const actor = requireAdmin(context, "Username migration requires administrator access.");
  return migratePage({
    db: getFirestore(), actor, cursor: data && data.cursor,
    pageSize: data && data.pageSize, dryRun: data && data.dryRun !== false,
  });
});

exports._candidateRowsForUser = candidateRowsForUser;
exports._planLegacyRows = planLegacyRows;
exports._migratePage = migratePage;
exports._statuses = STATUSES;
