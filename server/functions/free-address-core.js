/* eslint-disable max-len, require-jsdoc */

function text(value) {
  return `${value || ""}`.trim();
}

function sanitizeQuery(value, maxLength = 160) {
  return text(value).replace(/\s+/g, " ").slice(0, maxLength);
}

function nominatimSearchUrl(query) {
  const params = new URLSearchParams({
    format: "jsonv2",
    addressdetails: "1",
    countrycodes: "gb",
    limit: "6",
    q: sanitizeQuery(query),
  });
  return `https://nominatim.openstreetmap.org/search?${params.toString()}`;
}

function mapAddress(result) {
  const address = result.address || {};
  const road = text(address.road || address.pedestrian || address.footway || address.path);
  const houseNumber = text(address.house_number);
  const city = text(address.city || address.town || address.village || address.municipality || address.suburb);
  const county = text(address.county || address.state_district || address.state);
  const postcode = text(address.postcode).toUpperCase();
  const displayAddress = text(result.display_name);
  const lat = Number(result.lat);
  const lng = Number(result.lon);
  return {
    displayAddress,
    lat,
    lng,
    confidence: Number.isFinite(Number(result.importance)) ?
      Math.min(0.96, Math.max(0.82, 0.82 + Number(result.importance))) : 0.84,
    provider: "openstreetmap_nominatim",
    locationId: `${text(result.osm_type)}_${text(result.osm_id)}`.replace(/^_+|_+$/g, ""),
    components: {
      buildingNumber: houseNumber,
      street: road,
      city,
      county,
      postcode,
      country: text(address.country || "United Kingdom"),
    },
  };
}

function cleanComponents(components) {
  const cleaned = {};
  for (const [key, value] of Object.entries(components || {})) {
    if (text(value)) cleaned[key] = text(value);
  }
  return cleaned;
}

async function searchFreeUkAddresses({query, fetchImpl = global.fetch}) {
  const clean = sanitizeQuery(query);
  if (clean.length < 3) return {status: "ZERO_RESULTS", results: []};
  if (typeof fetchImpl !== "function") {
    throw new Error("Fetch is not available in this runtime.");
  }
  const response = await fetchImpl(nominatimSearchUrl(clean), {
    headers: {
      "Accept": "application/json",
      "User-Agent": "Circum/1.0 (address search; circumuk.com)",
    },
  });
  if (!response.ok) {
    return {status: "HTTP_ERROR", results: []};
  }
  const body = await response.json();
  return {
    status: Array.isArray(body) && body.length ? "OK" : "ZERO_RESULTS",
    results: (Array.isArray(body) ? body : [])
        .map(mapAddress)
        .filter((item) => item.displayAddress && Number.isFinite(item.lat) && Number.isFinite(item.lng))
        .map((item) => ({...item, components: cleanComponents(item.components)}))
        .slice(0, 6),
    attribution: "OpenStreetMap",
  };
}

module.exports = {
  nominatimSearchUrl,
  sanitizeQuery,
  searchFreeUkAddresses,
};
