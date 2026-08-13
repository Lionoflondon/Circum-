/* eslint-disable max-len, require-jsdoc */

const dns = require("node:dns");

// The backend Places key is restricted to the Functions' static IPv4 egress.
// Prefer IPv4 so Node fetch does not bypass that policy over an IPv6 route.
dns.setDefaultResultOrder("ipv4first");

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

function googlePlacesAutocompleteUrl(query, apiKey, sessionToken = "") {
  const params = new URLSearchParams({
    input: sanitizeQuery(query),
    key: text(apiKey),
    components: "country:gb",
    language: "en",
  });
  if (text(sessionToken)) params.set("sessiontoken", text(sessionToken));
  return `https://maps.googleapis.com/maps/api/place/autocomplete/json?${params.toString()}`;
}

function googlePlaceDetailsUrl(placeId, apiKey, sessionToken = "") {
  const params = new URLSearchParams({
    place_id: text(placeId),
    key: text(apiKey),
    language: "en",
    fields: "place_id,formatted_address,geometry,address_component,name",
  });
  if (text(sessionToken)) params.set("sessiontoken", text(sessionToken));
  return `https://maps.googleapis.com/maps/api/place/details/json?${params.toString()}`;
}

function googleGeocodeAddressUrl(query, apiKey) {
  const params = new URLSearchParams({
    address: sanitizeQuery(query),
    key: text(apiKey),
    components: "country:GB",
    language: "en",
  });
  return `https://maps.googleapis.com/maps/api/geocode/json?${params.toString()}`;
}

function premiseHint(query) {
  const clean = sanitizeQuery(query);
  const unit = clean.match(/\b(?:flat|apartment|apt|unit|suite)\s+[a-z0-9-]+\b/i);
  const withoutUnit = unit ? clean.replace(unit[0], " ") : clean;
  const house = withoutUnit.toLowerCase().match(/(?:^|[,\s])(\d+[a-z]?)(?=[,\s]+[a-z])/);
  return {
    unit: text(unit && unit[0]),
    houseNumber: text(house && house[1]),
  };
}

function samePremise(expected, actual) {
  const normalize = (value) => text(value).toLowerCase().replace(/\s+/g, "");
  return normalize(expected) && normalize(expected) === normalize(actual);
}

function mapAddress(result) {
  const address = result.address || {};
  const road = text(address.road || address.pedestrian || address.footway || address.path);
  const houseNumber = text(address.house_number);
  const city = text(address.city || address.town || address.village || address.municipality || address.suburb);
  const county = text(address.county || address.state_district || address.state);
  const postcode = text(address.postcode).toUpperCase();
  const displayAddress = houseNumber && road && !text(result.display_name).toLowerCase().includes(houseNumber.toLowerCase()) ?
    [houseNumber, road, city, county, postcode, text(address.country || "United Kingdom")].filter(Boolean).join(", ") :
    text(result.display_name);
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
      addressLine1: [houseNumber, road].map(text).filter(Boolean).join(" "),
      buildingNumber: houseNumber,
      street: road,
      city,
      county,
      postcode,
      country: text(address.country || "United Kingdom"),
    },
  };
}

function mapGooglePrediction(prediction, sourceInput = "") {
  const structured = prediction.structured_formatting || {};
  return {
    displayAddress: text(prediction.description),
    lat: null,
    lng: null,
    confidence: 0.98,
    provider: "google_places",
    locationId: text(prediction.place_id),
    placeId: text(prediction.place_id),
    sourceInput: sanitizeQuery(sourceInput),
    components: cleanComponents({
      addressLine1: text(structured.main_text),
      country: "United Kingdom",
    }),
  };
}

function googleAddressComponent(components, type) {
  const component = (components || []).find((item) => {
    const types = Array.isArray(item.types) ? item.types : [];
    return types.includes(type);
  });
  return text(component && component.long_name);
}

function mapGooglePlaceDetails(result) {
  const components = result.address_components || [];
  const location = result.geometry && result.geometry.location || {};
  const lat = Number(location.lat);
  const lng = Number(location.lng);
  const streetNumber = googleAddressComponent(components, "street_number");
  const route = googleAddressComponent(components, "route");
  const addressLine1 = [streetNumber, route].map(text).filter(Boolean).join(" ");
  const city = text(
      googleAddressComponent(components, "postal_town") ||
      googleAddressComponent(components, "locality") ||
      googleAddressComponent(components, "sublocality"));
  const county = text(
      googleAddressComponent(components, "administrative_area_level_2") ||
      googleAddressComponent(components, "administrative_area_level_1"));
  const postcode = text(googleAddressComponent(components, "postal_code")).toUpperCase();
  return {
    displayAddress: text(result.formatted_address || result.name),
    lat,
    lng,
    confidence: 0.99,
    provider: "google_places",
    locationId: text(result.place_id),
    placeId: text(result.place_id),
    components: cleanComponents({
      addressLine1,
      street: route,
      buildingNumber: streetNumber,
      city,
      county,
      postcode,
      country: googleAddressComponent(components, "country") || "United Kingdom",
    }),
  };
}

function mapGoogleGeocodeResult(result, sourceInput = "") {
  const components = result.address_components || [];
  const location = result.geometry && result.geometry.location || {};
  const lat = Number(location.lat);
  const lng = Number(location.lng);
  const streetNumber = googleAddressComponent(components, "street_number");
  const route = googleAddressComponent(components, "route");
  const hint = premiseHint(sourceInput);
  if (hint.houseNumber && !samePremise(hint.houseNumber, streetNumber)) return null;
  const addressLine1 = [streetNumber, route].map(text).filter(Boolean).join(" ");
  const city = text(
      googleAddressComponent(components, "postal_town") ||
      googleAddressComponent(components, "locality") ||
      googleAddressComponent(components, "sublocality"));
  const county = text(
      googleAddressComponent(components, "administrative_area_level_2") ||
      googleAddressComponent(components, "administrative_area_level_1"));
  const postcode = text(googleAddressComponent(components, "postal_code")).toUpperCase();
  const displayAddress = [hint.unit, addressLine1, city, county, postcode, googleAddressComponent(components, "country") || "United Kingdom"]
      .map(text)
      .filter(Boolean)
      .join(", ");
  return {
    displayAddress: displayAddress || text(result.formatted_address),
    lat,
    lng,
    confidence: 0.99,
    provider: "google_geocoding",
    locationId: text(result.place_id),
    placeId: text(result.place_id),
    sourceInput: sanitizeQuery(sourceInput),
    components: cleanComponents({
      addressLine1,
      street: route,
      buildingNumber: streetNumber,
      apartment: hint.unit,
      city,
      county,
      postcode,
      country: googleAddressComponent(components, "country") || "United Kingdom",
    }),
  };
}

function cleanComponents(components) {
  const cleaned = {};
  for (const [key, value] of Object.entries(components || {})) {
    if (text(value)) cleaned[key] = text(value);
  }
  return cleaned;
}

async function fetchJsonWithTimeout(url, {fetchImpl = global.fetch, headers = {}, timeoutMs = 6000} = {}) {
  const controller = typeof AbortController === "function" ? new AbortController() : null;
  const timeout = controller ? setTimeout(() => controller.abort(), timeoutMs) : null;
  try {
    const response = await fetchImpl(url, {
      headers: {
        "Accept": "application/json",
        ...headers,
      },
      ...(controller ? {signal: controller.signal} : {}),
    });
    if (!response.ok) return {ok: false, status: "HTTP_ERROR", body: null};
    return {ok: true, status: "OK", body: await response.json()};
  } finally {
    if (timeout) clearTimeout(timeout);
  }
}

async function searchNominatimUkAddresses({query, fetchImpl = global.fetch}) {
  const result = await fetchJsonWithTimeout(nominatimSearchUrl(query), {
    fetchImpl,
    headers: {"User-Agent": "Circum/1.0 (address search; circumuk.com)"},
  });
  if (!result.ok) return {status: result.status, results: []};
  const body = result.body;
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

async function searchGoogleUkAddresses({query, fetchImpl = global.fetch, googlePlacesApiKey = "", sessionToken = ""}) {
  const apiKey = text(googlePlacesApiKey);
  if (!apiKey) return {status: "MISSING_GOOGLE_PLACES_API_KEY", results: []};
  const result = await fetchJsonWithTimeout(googlePlacesAutocompleteUrl(query, apiKey, sessionToken), {fetchImpl});
  if (!result.ok) return {status: result.status, results: []};
  const body = result.body || {};
  if (body.status !== "OK") {
    return {status: body.status || "ZERO_RESULTS", results: [], provider: "google_places"};
  }
  return {
    status: "OK",
    results: (Array.isArray(body.predictions) ? body.predictions : [])
        .map((item) => mapGooglePrediction(item, query))
        .filter((item) => item.displayAddress && item.placeId)
        .slice(0, 6),
    attribution: "Google Places",
  };
}

async function searchGooglePremiseUkAddresses({query, fetchImpl = global.fetch, googlePlacesApiKey = ""}) {
  const apiKey = text(googlePlacesApiKey);
  const hint = premiseHint(query);
  if (!apiKey || !hint.houseNumber) return {status: "ZERO_RESULTS", results: [], provider: "google_geocoding"};
  const result = await fetchJsonWithTimeout(googleGeocodeAddressUrl(query, apiKey), {fetchImpl});
  if (!result.ok) return {status: result.status, results: [], provider: "google_geocoding"};
  const body = result.body || {};
  if (body.status !== "OK") {
    return {status: body.status || "ZERO_RESULTS", results: [], provider: "google_geocoding"};
  }
  const results = (Array.isArray(body.results) ? body.results : [])
      .map((item) => mapGoogleGeocodeResult(item, query))
      .filter((item) => item && item.displayAddress && Number.isFinite(item.lat) && Number.isFinite(item.lng))
      .slice(0, 2);
  return {
    status: results.length ? "OK" : "ZERO_RESULTS",
    results,
    attribution: "Google Geocoding",
  };
}

async function resolveUkAddressPlace({placeId, fetchImpl = global.fetch, googlePlacesApiKey = "", sessionToken = ""}) {
  const apiKey = text(googlePlacesApiKey);
  const cleanPlaceId = text(placeId);
  if (!apiKey) throw new Error("GOOGLE_PLACES_API_KEY is not configured.");
  if (!cleanPlaceId) throw new Error("placeId is required.");
  const result = await fetchJsonWithTimeout(googlePlaceDetailsUrl(cleanPlaceId, apiKey, sessionToken), {fetchImpl});
  if (!result.ok) throw new Error("Google Places details request failed.");
  const body = result.body || {};
  if (body.status !== "OK" || !body.result) {
    throw new Error(`Google Places details returned ${body.status || "UNKNOWN"}.`);
  }
  const mapped = mapGooglePlaceDetails(body.result);
  if (!mapped.displayAddress || !Number.isFinite(mapped.lat) || !Number.isFinite(mapped.lng)) {
    throw new Error("Google Places details did not include a usable coordinate.");
  }
  return mapped;
}

async function searchFreeUkAddresses({
  query,
  fetchImpl = global.fetch,
  googlePlacesApiKey = process.env.GOOGLE_PLACES_API_KEY || "",
  sessionToken = "",
}) {
  const clean = sanitizeQuery(query);
  if (clean.length < 3) return {status: "ZERO_RESULTS", results: []};
  if (typeof fetchImpl !== "function") {
    throw new Error("Fetch is not available in this runtime.");
  }

  const googleResult = await searchGoogleUkAddresses({
    query: clean,
    fetchImpl,
    googlePlacesApiKey,
    sessionToken,
  });
  if (googleResult.status === "OK" && googleResult.results.length) {
    const premiseResult = await searchGooglePremiseUkAddresses({
      query: clean,
      fetchImpl,
      googlePlacesApiKey,
    });
    if (premiseResult.status === "OK" && premiseResult.results.length) {
      const seen = new Set();
      const results = [...premiseResult.results, ...googleResult.results]
          .filter((item) => {
            const key = text(item.placeId || item.locationId || item.displayAddress);
            if (!key || seen.has(key)) return false;
            seen.add(key);
            return true;
          })
          .slice(0, 6);
      return {...googleResult, results, premiseAttribution: premiseResult.attribution};
    }
    return googleResult;
  }

  const fallback = await searchNominatimUkAddresses({query: clean, fetchImpl});
  return {
    ...fallback,
    fallbackReason: googleResult.status,
  };
}

module.exports = {
  googlePlacesAutocompleteUrl,
  googlePlaceDetailsUrl,
  googleGeocodeAddressUrl,
  nominatimSearchUrl,
  premiseHint,
  resolveUkAddressPlace,
  sanitizeQuery,
  searchFreeUkAddresses,
  searchGooglePremiseUkAddresses,
  searchGoogleUkAddresses,
  searchNominatimUkAddresses,
};
