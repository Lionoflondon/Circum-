/* global AggregateError */
"use strict";

// Test teardown must never run while another caller in a failed race is active.
module.exports = async function settleConcurrent(promises) {
  const results = await Promise.allSettled(promises);
  const errors = results.filter((result) => result.status === "rejected")
    .map((result) => result.reason);
  if (errors.length) {
    throw new AggregateError(errors, errors.map((error) => error.message).join("; "));
  }
  return results.map((result) => result.value);
};
