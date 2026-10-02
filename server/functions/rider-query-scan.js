"use strict";
/* eslint-disable require-jsdoc */

// Snapshot cursors preserve the query's ordering, including tied field values.
async function scanQuery(query, pageSize, visit) {
  let cursor;
  for (;;) {
    let pageQuery = query.limit(pageSize);
    if (cursor) pageQuery = pageQuery.startAfter(cursor);
    const page = await pageQuery.get();
    for (const doc of page.docs) await visit(doc);
    if (page.docs.length < pageSize) return;
    cursor = page.docs[page.docs.length - 1];
  }
}

module.exports = {scanQuery};
