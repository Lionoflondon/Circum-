"use strict";

const TRUSTED_PROVIDERS = new Set(["google_places", "openstreetmap_nominatim", "saved_google_place", "backend_verified"]);

function text(value) {
  return `${value == null ? "" : value}`.trim();
}

function canonicalAddress(value, role = "address") {
  const input = value && typeof value === "object" && !Array.isArray(value) ? value : {};
  const latitude = Number(input.latitude ?? input.lat);
  const longitude = Number(input.longitude ?? input.lng);
  const provider = text(input.provider || input.addressSource);
  const placeId = text(input.placeId || input.locationId);
  const validationStatus = text(input.validationStatus).toLowerCase();
  const country = text(input.country).toLowerCase();
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude) ||
      latitude < 49.8 || latitude > 58.8 || longitude < -8.8 || longitude > 2.1) {
    const error = new Error(`${role} requires a valid UK coordinate.`);
    error.code = "canonical_address_coordinates_required";
    throw error;
  }
  if (!placeId || !provider || !TRUSTED_PROVIDERS.has(provider) || validationStatus !== "verified") {
    const error = new Error(`${role} must be a verified canonical address.`);
    error.code = "canonical_address_verification_required";
    throw error;
  }
  if (country && country !== "uk" && country !== "gb" && !country.includes("united kingdom")) {
    const error = new Error(`${role} must be in the United Kingdom.`);
    error.code = "canonical_address_country_invalid";
    throw error;
  }
  return {
    formattedAddress: text(input.formattedAddress || input.displayAddress || input.description),
    addressLine1: text(input.addressLine1 || input.street || input.mainText),
    addressLine2: text(input.addressLine2 || input.subAddress),
    city: text(input.city || input.locality),
    county: text(input.county),
    postcode: text(input.postcode),
    country: text(input.country || "United Kingdom"),
    placeId,
    locationId: text(input.locationId || placeId),
    provider,
    validationStatus: "verified",
    latitude,
    longitude,
    coordinates: {latitude, longitude},
  };
}

function canonicalAddressPair(data = {}) {
  const pickup = canonicalAddress(
      data.pickupAddressCanonical || data.pickup && data.pickup.canonicalAddress,
      "pickup address",
  );
  const dropoff = canonicalAddress(
      data.dropoffAddressCanonical || data.dropoff && data.dropoff.canonicalAddress,
      "drop-off address",
  );
  return {pickup, dropoff};
}

function sameCanonicalAddress(left, right) {
  return Boolean(left && right) &&
    (left.placeId === right.placeId || left.locationId === right.locationId) &&
    Math.abs(Number(left.latitude) - Number(right.latitude)) < 0.000001 &&
    Math.abs(Number(left.longitude) - Number(right.longitude)) < 0.000001;
}

module.exports = {TRUSTED_PROVIDERS, canonicalAddress, canonicalAddressPair, sameCanonicalAddress};
