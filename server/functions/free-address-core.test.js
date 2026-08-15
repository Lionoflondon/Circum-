/* eslint-disable max-len */
const test = require("node:test");
const assert = require("node:assert/strict");
const {
  googlePlaceDetailsUrl,
  googlePlacesAutocompleteUrl,
  resolveUkAddressPlace,
  premiseHint,
  sanitizeQuery,
  searchFreeUkAddresses,
} = require("./free-address-core");

test("sanitizes address queries", () => {
  assert.equal(sanitizeQuery("  Harley   Street   London  "), "Harley Street London");
  assert.equal(sanitizeQuery("ab"), "ab");
});

test("extracts flat and premise hints without stripping delivery detail", () => {
  assert.deepEqual(premiseHint("Flat 190, 4 Edridge Road, CR0 1GD"), {
    apartment: "Flat 190",
    buildingNumber: "4",
  });
  assert.deepEqual(premiseHint("4 Edridge Road, Flat 190, CR0 1GD"), {
    apartment: "Flat 190",
    buildingNumber: "4",
  });
});

test("builds a paid Google Places UK autocomplete URL", () => {
  const url = googlePlacesAutocompleteUrl("29 St Fillans Road SE6 1DQ", "test-key", "session-1");
  assert.match(url, /maps\.googleapis\.com\/maps\/api\/place\/autocomplete\/json/);
  assert.match(url, /components=country%3Agb/);
  assert.match(url, /sessiontoken=session-1/);
  assert.match(url, /key=test-key/);
});

test("uses Google Places autocomplete when a paid key is configured", async () => {
  const seenUrls = [];
  const fetchImpl = async (url, options) => {
    seenUrls.push(url);
    assert.equal(options.signal instanceof AbortSignal, true);
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
  assert.equal(seenUrls.length, 1);
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

test("Google autocomplete preserves flat hint for matching premise prediction", async () => {
  const fetchImpl = async (url) => {
    assert.match(url, /maps\.googleapis\.com\/maps\/api\/place\/autocomplete\/json/);
    return {
      ok: true,
      async json() {
        return {
          status: "OK",
          predictions: [{
            place_id: "google-edridge-4",
            description: "4 Edridge Road, Croydon CR0 1GD, UK",
            structured_formatting: {main_text: "4 Edridge Road"},
          }],
        };
      },
    };
  };
  const result = await searchFreeUkAddresses({
    query: "Flat 190, 4 Edridge Road, CR0 1GD",
    fetchImpl,
    googlePlacesApiKey: "paid-google-key",
    sessionToken: "session-1",
  });
  assert.equal(result.status, "OK");
  assert.equal(result.results[0].displayAddress, "Flat 190, 4 Edridge Road, Croydon CR0 1GD, UK");
  assert.equal(result.results[0].components.apartment, "Flat 190");
  assert.equal(result.results[0].components.buildingNumber, "4");
  assert.equal(result.results[0].components.resolutionPrecision, "unit");
});

test("Google place details preserves flat only when the building matches", async () => {
  const fetchImpl = async (requestUrl) => {
    assert.match(requestUrl, /maps\.googleapis\.com\/maps\/api\/place\/details\/json/);
    return {
      ok: true,
      async json() {
        return {
          status: "OK",
          result: {
            place_id: "google-edridge-4",
            formatted_address: "4 Edridge Road, Croydon CR0 1GD, UK",
            geometry: {location: {lat: 51.3728, lng: -0.1007}},
            address_components: [
              {long_name: "4", types: ["street_number"]},
              {long_name: "Edridge Road", types: ["route"]},
              {long_name: "Croydon", types: ["postal_town"]},
              {long_name: "Greater London", types: ["administrative_area_level_2"]},
              {long_name: "CR0 1GD", types: ["postal_code"]},
              {long_name: "United Kingdom", types: ["country"]},
            ],
          },
        };
      },
    };
  };
  const result = await resolveUkAddressPlace({
    placeId: "google-edridge-4",
    sourceInput: "Flat 190, 4 Edridge Road, CR0 1GD",
    fetchImpl,
    googlePlacesApiKey: "paid-google-key",
    sessionToken: "session-1",
  });
  assert.equal(result.displayAddress, "Flat 190, 4 Edridge Road, Croydon CR0 1GD, UK");
  assert.equal(result.components.apartment, "Flat 190");
  assert.equal(result.components.buildingNumber, "4");
  assert.equal(result.components.resolutionPrecision, "unit");
});

test("Google Places is required for operational address search", async () => {
  const fetchImpl = async (url, options) => {
    assert.match(url, /maps\.googleapis\.com\/maps\/api\/place\/autocomplete\/json/);
    assert.equal(options.signal instanceof AbortSignal, true);
    return {
      ok: true,
      async json() {
        return {status: "OK", predictions: []};
      },
    };
  };
  const result = await searchFreeUkAddresses({
    query: "Harley Street London",
    fetchImpl,
    googlePlacesApiKey: "paid-google-key",
  });
  assert.equal(result.status, "OK");
  assert.equal(result.attribution, "Google Places");
  assert.deepEqual(result.results, []);
});

test("does not fall back to OpenStreetMap when Google Places is unavailable", async () => {
  const seenUrls = [];
  const fetchImpl = async (url) => {
    seenUrls.push(url);
    return {
      ok: true,
      async json() {
        return {status: "REQUEST_DENIED", predictions: []};
      },
    };
  };
  const result = await searchFreeUkAddresses({
    query: "Harley Street London",
    fetchImpl,
    googlePlacesApiKey: "bad-key",
  });
  assert.equal(result.status, "REQUEST_DENIED");
  assert.deepEqual(result.results, []);
  assert.deepEqual(seenUrls.map((url) => url.includes("maps.googleapis.com")), [true]);
});

test("address search uses an abortable backend timeout", () => {
  const source = require("node:fs").readFileSync("free-address-core.js", "utf8");
  assert.match(source, /new AbortController\(\)/);
  assert.match(source, /timeoutMs = 6000/);
  assert.match(source, /setTimeout\(\(\) => controller\.abort\(\), timeoutMs\)/);
  assert.match(source, /signal: controller\.signal/);
  assert.match(source, /clearTimeout\(timeout\)/);
});
