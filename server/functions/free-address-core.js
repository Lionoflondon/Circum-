/* eslint-disable max-len, require-jsdoc */

function text(value) {
  return `${value || ""}`.trim();
}

function sanitizeQuery(value, maxLength = 160) {
  return text(value).replace(/\s+/g, " ").slice(0, maxLength);
}

function premiseHint(value) {
  const query = sanitizeQuery(value);
  const unitMatch = query.match(/\b(flat|apartment|apt|unit|suite)\s*([a-z0-9-]+)\b/i);
  const apartment = unitMatch ? `${unitMatch[1]} ${unitMatch[2]}` : "";
  const withoutUnit = apartment ?
    query.replace(unitMatch[0], " ").replace(/\s*,\s*/g, " ").replace(/\s+/g, " ").trim() :
    query;
  const numberMatch = withoutUnit.match(/\b(\d+[a-z]?)\s+([a-z][a-z\s.'-]*?)(?:\s*,?\s*[A-Z]{1,2}\d[A-Z\d]?\s*\d[A-Z]{2}\b|,|$)/i);
  return {
    apartment,
    buildingNumber: numberMatch ? numberMatch[1] : "",
  };
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

function mapGooglePrediction(prediction, sourceInput = "") {
  const structured = prediction.structured_formatting || {};
  const hint = premiseHint(sourceInput);
  const mainText = text(structured.main_text);
  const predictionHasBuilding = hint.buildingNumber &&
    new RegExp(`(^|\\D)${hint.buildingNumber}(\\D|$)`).test(mainText);
  const displayAddress = text(prediction.description);
  const displayWithUnit = hint.apartment && predictionHasBuilding &&
    !displayAddress.toLowerCase().includes(hint.apartment.toLowerCase()) ?
    `${hint.apartment}, ${displayAddress}` :
    displayAddress;
  return {
    displayAddress: displayWithUnit,
    lat: null,
    lng: null,
    confidence: 0.98,
    provider: "google_places",
    locationId: text(prediction.place_id),
    placeId: text(prediction.place_id),
    sourceInput: sanitizeQuery(sourceInput),
    components: cleanComponents({
      addressLine1: mainText,
      apartment: predictionHasBuilding ? hint.apartment : "",
      buildingNumber: predictionHasBuilding ? hint.buildingNumber : "",
      country: "United Kingdom",
      resolutionPrecision: predictionHasBuilding && hint.apartment ? "unit" : "",
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

function mapGooglePlaceDetails(result, sourceInput = "") {
  const components = result.address_components || [];
  const location = result.geometry && result.geometry.location || {};
  const lat = Number(location.lat);
  const lng = Number(location.lng);
  const hint = premiseHint(sourceInput);
  const streetNumber = googleAddressComponent(components, "street_number");
  const route = googleAddressComponent(components, "route");
  const apartment = hint.apartment && hint.buildingNumber &&
    text(hint.buildingNumber).toLowerCase() === text(streetNumber).toLowerCase() ?
    hint.apartment :
    "";
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
    displayAddress: apartment ?
      `${apartment}, ${text(result.formatted_address || result.name)}` :
      text(result.formatted_address || result.name),
    lat,
    lng,
    confidence: 0.99,
    provider: "google_places",
    locationId: text(result.place_id),
    placeId: text(result.place_id),
    components: cleanComponents({
      addressLine1,
      apartment,
      street: route,
      buildingNumber: streetNumber,
      city,
      county,
      postcode,
      country: googleAddressComponent(components, "country") || "United Kingdom",
      resolutionPrecision: apartment ? "unit" : streetNumber ? "premise" : route ? "street" : "",
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

async function resolveUkAddressPlace({placeId, sourceInput = "", fetchImpl = global.fetch, googlePlacesApiKey = "", sessionToken = ""}) {
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
  const mapped = mapGooglePlaceDetails(body.result, sourceInput);
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
  nominatimSearchUrl,
  resolveUkAddressPlace,
  sanitizeQuery,
  premiseHint,
  searchFreeUkAddresses,
  searchGoogleUkAddresses,
  searchNominatimUkAddresses,
};
