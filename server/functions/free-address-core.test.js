/* eslint-disable max-len */
const test = require("node:test");
const assert = require("node:assert/strict");
const {
  googlePlaceDetailsUrl,
  googlePlacesAutocompleteUrl,
  resolveUkAddressPlace,
  sanitizeQuery,
  searchFreeUkAddresses,
} = require("./free-address-core");

test("sanitizes address queries", () => {
  assert.equal(sanitizeQuery("  Harley   Street   London  "), "Harley Street London");
  assert.equal(sanitizeQuery("ab"), "ab");
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

test("does not restrict autocomplete to street addresses", async () => {
  let requestUrl = "";
  const result = await searchFreeUkAddresses({
    query: "King's Cross Station",
    googlePlacesApiKey: "paid-google-key",
    fetchImpl: async (url) => {
      requestUrl = url;
      return {
        ok: true,
        async json() {
          return {
            status: "OK",
            predictions: [{
              place_id: "station-1",
              description: "King's Cross Station, London, UK",
              structured_formatting: {main_text: "King's Cross Station"},
            }],
          };
        },
      };
    },
  });
  assert.equal(result.results[0].placeId, "station-1");
  assert.doesNotMatch(requestUrl, /types=address/);
  assert.doesNotMatch(requestUrl, /type=address/);
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

test("accepts named businesses and POIs without a street number", async () => {
  const result = await resolveUkAddressPlace({
    placeId: "hospital-1",
    fetchImpl: async () => ({
      ok: true,
      async json() {
        return {
          status: "OK",
          result: {
            place_id: "hospital-1",
            name: "St Thomas' Hospital",
            formatted_address: "St Thomas' Hospital, London SE1 7EH, UK",
            geometry: {location: {lat: 51.4988, lng: -0.1187}},
            address_components: [
              {long_name: "London", types: ["postal_town"]},
              {long_name: "SE1 7EH", types: ["postal_code"]},
              {long_name: "United Kingdom", types: ["country"]},
            ],
          },
        };
      },
    }),
    googlePlacesApiKey: "paid-google-key",
  });
  assert.equal(result.provider, "google_places");
  assert.equal(result.displayAddress, "St Thomas' Hospital, London SE1 7EH, UK");
  assert.equal(result.lat, 51.4988);
  assert.equal(result.lng, -0.1187);
});

test("returns the Google failure so the UI can keep manual entry available", async () => {
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
  assert.equal(result.provider, "google_places");
  assert.deepEqual(seenUrls.map((url) => url.includes("maps.googleapis.com")), [true]);
});

test("has no runtime Nominatim or OpenStreetMap geocoder", () => {
  const source = require("node:fs").readFileSync("free-address-core.js", "utf8");
  assert.doesNotMatch(source, /nominatim/i);
  assert.doesNotMatch(source, /openstreetmap/i);
  assert.doesNotMatch(source, /searchNominatimUkAddresses/);
});

test("address search uses an abortable backend timeout", () => {
  const source = require("node:fs").readFileSync("free-address-core.js", "utf8");
  assert.match(source, /new AbortController\(\)/);
  assert.match(source, /timeoutMs = 6000/);
  assert.match(source, /setTimeout\(\(\) => controller\.abort\(\), timeoutMs\)/);
  assert.match(source, /signal: controller\.signal/);
  assert.match(source, /clearTimeout\(timeout\)/);
});
