"use strict";

const SERVICE_NAMES = Object.freeze([
  "delivery", "dispatch", "pricing", "tracking", "evidence",
  "settlement", "notification", "analytics",
]);

function createPlatformServices(services = {}) {
  const missing = SERVICE_NAMES.filter((name) => typeof services[name] !== "object" || services[name] === null);
  if (missing.length) throw new TypeError(`Missing platform services: ${missing.join(", ")}`);
  return Object.freeze({...services});
}

function requireOperation(service, operation) {
  if (!service || typeof service[operation] !== "function") {
    throw new TypeError(`Service operation is not implemented: ${operation}`);
  }
  return service[operation];
}

module.exports = {SERVICE_NAMES, createPlatformServices, requireOperation};
