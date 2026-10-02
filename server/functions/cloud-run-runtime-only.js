"use strict";

// Keep a callable available to Cloud Run without Firebase deployment metadata.
function cloudRunOnly(callable, owner, appCheckRequired = false) {
  if (!callable || typeof callable.run !== "function" || !owner) {
    throw new TypeError("A callable handler and its Cloud Run owner are required");
  }
  const handler = (...args) => {
    if (typeof callable !== "function") throw new TypeError("An HTTP callable is required");
    return callable(...args);
  };
  handler.run = (...args) => callable.run(...args);
  Object.defineProperty(handler, "_cloudRunOnly", {value: Object.freeze({
    owner,
    appCheckRequired: Boolean(appCheckRequired),
  })});
  return Object.freeze(handler);
}

module.exports = {cloudRunOnly};
