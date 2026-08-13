/* eslint-disable max-len */
const test = require("node:test");
const assert = require("node:assert/strict");
const {
  googleGeocodeAddressUrl,
  googlePlaceDetailsUrl,
  googlePlacesAutocompleteUrl,
  nominatimSearchUrl,
  premiseHint,
  resolveUkAddressPlace,
  sanitizeQuery,
  searchFreeUkAddresses,
  searchGooglePremiseUkAddresses,
} = require("./free-address-core");

test("sanitizes address queries", () => {
  assert.equal(sanitizeQuery("  Harley   Street   London  "), "Harley Street London");
  assert.equal(sanitizeQuery("ab"), "ab");
});

test("builds a free UK-only Nominatim search URL", () => {
  const url = nominatimSearchUrl("Harley Street London");
  assert.match(url, /nominatim\.openstreetmap\.org\/search/);
  assert.match(url, /countrycodes=gb/);
  assert.match(url, /addressdetails=1/);
  assert.doesNotMatch(url, /maps\.googleapis\.com/);
});

test("builds a paid Google Places UK autocomplete URL", () => {
  const url = googlePlacesAutocompleteUrl("29 St Fillans Road SE6 1DQ", "test-key", "session-1");
  assert.match(url, /maps\.googleapis\.com\/maps\/api\/place\/autocomplete\/json/);
  assert.match(url, /components=country%3Agb/);
  assert.match(url, /sessiontoken=session-1/);
  assert.match(url, /key=test-key/);
});

test("extracts premise and flat details without stripping house numbers", () => {
  assert.deepEqual(premiseHint("29 St Fillans Road SE6 1DQ"), {
    unit: "",
    houseNumber: "29",
  });
  assert.deepEqual(premiseHint("29, ST FILLANS ROAD SE6 1DQ"), {
    unit: "",
    houseNumber: "29",
  });
  assert.deepEqual(premiseHint("Flat 4, 29 St Fillans Road SE6 1DQ"), {
    unit: "Flat 4",
    houseNumber: "29",
  });
  assert.deepEqual(premiseHint("St Fillans Road SE6 1DQ"), {
    unit: "",
    houseNumber: "",
  });
});

test("uses Google Places autocomplete when a paid key is configured", async () => {
  const seenUrls = [];
  const fetchImpl = async (url, options) => {
    seenUrls.push(url);
    assert.equal(options.signal instanceof AbortSignal, true);
    if (url.includes("/geocode/")) {
      return {
        ok: true,
        async json() {
          return {status: "ZERO_RESULTS", results: []};
        },
      };
    }
    assert.match(url, /maps\.googleapis\.com\/maps\/api\/place\/autocomplete\/json/);
    return {
      ok: true,
      async json() {
        return {
          status: "OK",
          predictions: [{
            place_id: "google-place-1",
            description: "29 St Fillans Road, London SE6 1DQ, UK",
            structured_formatting: {main_text: "29 St Fillans Road"},
          }],
        };
      },
    };
  };
  const result = await searchFreeUkAddresses({
    query: "29 St Fillans Road SE6 1DQ",
    fetchImpl,
    googlePlacesApiKey: "paid-google-key",
    sessionToken: "session-1",
  });
  assert.equal(result.status, "OK");
  assert.equal(result.attribution, "Google Places");
  assert.equal(result.results[0].provider, "google_places");
  assert.equal(result.results[0].placeId, "google-place-1");
  assert.equal(result.results[0].lat, null);
  assert.equal(seenUrls.length, 2);
  assert.match(seenUrls[0], /maps\.googleapis\.com\/maps\/api\/place\/autocomplete\/json/);
  assert.match(seenUrls[1], /maps\.googleapis\.com\/maps\/api\/geocode\/json/);
});

test("numbered Google searches prefer authoritative premise geocode results", async () => {
  const seenUrls = [];
  const fetchImpl = async (url) => {
    seenUrls.push(url);
    if (url.includes("/place/autocomplete/")) {
      return {
        ok: true,
        async json() {
          return {
            status: "OK",
            predictions: [{
              place_id: "street-level",
              description: "St Fillans Road, Greater London, England, SE6 1DQ, UK",
              structured_formatting: {main_text: "St Fillans Road"},
            }],
          };
        },
      };
    }
    assert.match(url, /maps\.googleapis\.com\/maps\/api\/geocode\/json/);
    return {
      ok: true,
      async json() {
        return {
          status: "OK",
          results: [{
            place_id: "premise-29",
            formatted_address: "29 St Fillans Road, London SE6 1DQ, UK",
            geometry: {location: {lat: 51.4401, lng: -0.0258}},
            address_components: [
              {long_name: "29", types: ["street_number"]},
              {long_name: "St Fillans Road", types: ["route"]},
              {long_name: "London", types: ["postal_town"]},
              {long_name: "Greater London", types: ["administrative_area_level_2"]},
              {long_name: "SE6 1DQ", types: ["postal_code"]},
              {long_name: "United Kingdom", types: ["country"]},
            ],
          }],
        };
      },
    };
  };
  const result = await searchFreeUkAddresses({
    query: "29 St Fillans Road SE6 1DQ",
    fetchImpl,
    googlePlacesApiKey: "paid-google-key",
  });
  assert.equal(result.status, "OK");
  assert.equal(result.results[0].placeId, "premise-29");
  assert.equal(result.results[0].displayAddress, "29 St Fillans Road, London, Greater London, SE6 1DQ, United Kingdom");
  assert.equal(result.results[0].components.buildingNumber, "29");
  assert.equal(result.results[0].components.addressLine1, "29 St Fillans Road");
  assert.equal(result.results[1].placeId, "street-level");
  assert.equal(seenUrls.some((url) => url.includes("/geocode/json")), true);
});

test("flat details are preserved only after the building premise is verified", async () => {
  assert.match(googleGeocodeAddressUrl("Flat 4, 29 St Fillans Road SE6 1DQ", "test-key"), /geocode\/json/);
  const fetchImpl = async () => ({
    ok: true,
    async json() {
      return {
        status: "OK",
        results: [{
          place_id: "premise-29",
          formatted_address: "29 St Fillans Road, London SE6 1DQ, UK",
          geometry: {location: {lat: 51.4401, lng: -0.0258}},
          address_components: [
            {long_name: "29", types: ["street_number"]},
            {long_name: "St Fillans Road", types: ["route"]},
            {long_name: "London", types: ["postal_town"]},
            {long_name: "SE6 1DQ", types: ["postal_code"]},
            {long_name: "United Kingdom", types: ["country"]},
          ],
        }],
      };
    },
  });
  const result = await searchGooglePremiseUkAddresses({
    query: "Flat 4, 29 St Fillans Road SE6 1DQ",
    fetchImpl,
    googlePlacesApiKey: "paid-google-key",
  });
  assert.equal(result.status, "OK");
  assert.equal(result.results[0].displayAddress, "Flat 4, 29 St Fillans Road, London, SE6 1DQ, United Kingdom");
  assert.equal(result.results[0].components.apartment, "Flat 4");
  assert.equal(result.results[0].components.buildingNumber, "29");
});

test("invalid numbered queries do not fabricate a premise", async () => {
  const fetchImpl = async () => ({
    ok: true,
    async json() {
      return {
        status: "OK",
        results: [{
          place_id: "different-premise",
          formatted_address: "31 St Fillans Road, London SE6 1DQ, UK",
          geometry: {location: {lat: 51.4401, lng: -0.0258}},
          address_components: [
            {long_name: "31", types: ["street_number"]},
            {long_name: "St Fillans Road", types: ["route"]},
            {long_name: "London", types: ["postal_town"]},
            {long_name: "SE6 1DQ", types: ["postal_code"]},
            {long_name: "United Kingdom", types: ["country"]},
          ],
        }],
      };
    },
  });
  const result = await searchGooglePremiseUkAddresses({
    query: "999 St Fillans Road SE6 1DQ",
    fetchImpl,
    googlePlacesApiKey: "paid-google-key",
  });
  assert.equal(result.status, "ZERO_RESULTS");
  assert.deepEqual(result.results, []);
});

test("resolves a selected Google place into coordinates and address components", async () => {
  const url = googlePlaceDetailsUrl("google-place-1", "test-key", "session-1");
  assert.match(url, /place_id=google-place-1/);
  const fetchImpl = async (requestUrl) => {
    assert.match(requestUrl, /maps\.googleapis\.com\/maps\/api\/place\/details\/json/);
    return {
      ok: true,
      async json() {
        return {
          status: "OK",
          result: {
            place_id: "google-place-1",
            formatted_address: "29 St Fillans Road, London SE6 1DQ, UK",
            geometry: {location: {lat: 51.4401, lng: -0.0258}},
            address_components: [
              {long_name: "29", types: ["street_number"]},
              {long_name: "St Fillans Road", types: ["route"]},
              {long_name: "London", types: ["postal_town"]},
              {long_name: "Greater London", types: ["administrative_area_level_2"]},
              {long_name: "SE6 1DQ", types: ["postal_code"]},
              {long_name: "United Kingdom", types: ["country"]},
            ],
          },
        };
      },
    };
  };
  const result = await resolveUkAddressPlace({
    placeId: "google-place-1",
    fetchImpl,
    googlePlacesApiKey: "paid-google-key",
    sessionToken: "session-1",
  });
  assert.equal(result.provider, "google_places");
  assert.equal(result.lat, 51.4401);
  assert.equal(result.lng, -0.0258);
  assert.equal(result.components.addressLine1, "29 St Fillans Road");
  assert.equal(result.components.postcode, "SE6 1DQ");
});

test("maps free address search results into Circum address suggestions", async () => {
  const fetchImpl = async (url, options) => {
    assert.match(url, /nominatim\.openstreetmap\.org/);
    assert.equal(options.signal instanceof AbortSignal, true);
    return {
      ok: true,
      async json() {
        return [{
          osm_type: "way",
          osm_id: 502230296,
          lat: "51.5181037",
          lon: "-0.1465558",
          importance: 0.05,
          display_name: "Harley Street, Marylebone, London, W1G 9QU, United Kingdom",
          address: {
            road: "Harley Street",
            city: "City of Westminster",
            postcode: "W1G 9QU",
            country: "United Kingdom",
          },
        }];
      },
    };
  };
  const result = await searchFreeUkAddresses({
    query: "Harley Street London",
    fetchImpl,
    googlePlacesApiKey: "",
  });
  assert.equal(result.status, "OK");
  assert.equal(result.attribution, "OpenStreetMap");
  assert.equal(result.results.length, 1);
  assert.equal(result.results[0].provider, "openstreetmap_nominatim");
  assert.equal(result.results[0].components.postcode, "W1G 9QU");
  assert.equal(result.results[0].lat, 51.5181037);
});

test("falls back to Nominatim when Google Places is unavailable", async () => {
  const seenUrls = [];
  const fetchImpl = async (url) => {
    seenUrls.push(url);
    if (url.includes("maps.googleapis.com")) {
      return {
        ok: true,
        async json() {
          return {status: "REQUEST_DENIED", predictions: []};
        },
      };
    }
    return {
      ok: true,
      async json() {
        return [{
          osm_type: "way",
          osm_id: 502230296,
          lat: "51.5181037",
          lon: "-0.1465558",
          display_name: "Harley Street, London, W1G 9QU, United Kingdom",
          address: {road: "Harley Street", city: "London", postcode: "W1G 9QU"},
        }];
      },
    };
  };
  const result = await searchFreeUkAddresses({
    query: "Harley Street London",
    fetchImpl,
    googlePlacesApiKey: "bad-key",
  });
  assert.equal(result.status, "OK");
  assert.equal(result.fallbackReason, "REQUEST_DENIED");
  assert.equal(result.attribution, "OpenStreetMap");
  assert.deepEqual(seenUrls.map((url) => url.includes("maps.googleapis.com")), [true, false]);
});

test("address search uses an abortable backend timeout", () => {
  const source = require("node:fs").readFileSync("free-address-core.js", "utf8");
  assert.match(source, /new AbortController\(\)/);
  assert.match(source, /timeoutMs = 6000/);
  assert.match(source, /setTimeout\(\(\) => controller\.abort\(\), timeoutMs\)/);
  assert.match(source, /signal: controller\.signal/);
  assert.match(source, /clearTimeout\(timeout\)/);
});
